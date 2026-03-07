import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';

import '../models/body_blog_entry.dart';
import '../models/body_blog_version.dart';
import '../models/capture_entry.dart';
import 'ambient_scan_service.dart';
import 'calendar_service.dart';
import 'health_service.dart';
import 'journal_ai_service.dart';
import 'local_db_service.dart';
import 'location_service.dart';

/// Service that collects real device data and generates a daily body-blog
/// narrative.
///
/// In v1 the narrative is composed locally from templates. In a future
/// version this will call an LLM endpoint (OpenAI / Gemini / local model)
/// with the [BodySnapshot] as structured context.
class BodyBlogService {
  final HealthService _health;
  final LocationService _location;
  final CalendarService _calendar;
  final AmbientScanService _ambient;
  final LocalDbService _db;
  final JournalAiService _ai;

  BodyBlogService({
    HealthService? health,
    LocationService? location,
    CalendarService? calendar,
    AmbientScanService? ambient,
    LocalDbService? db,
    JournalAiService? ai,
  }) : _health = health ?? HealthService(),
       _location = location ?? LocationService(),
       _calendar = calendar ?? CalendarService(),
       _ambient = ambient ?? AmbientScanService(),
       _db = db ?? LocalDbService(),
       _ai = ai ?? JournalAiService();

  // ── public API ──────────────────────────────────────────────────

  /// Return today's journal entry **instantly** when possible.
  ///
  /// Logic:
  /// 1. If a persisted entry exists for today **and** there are zero
  ///    unprocessed captures for today → return immediately (no sensors,
  ///    no AI call).
  /// 2. If a persisted entry exists but new (unprocessed) captures arrived
  ///    → run AI enrichment with *only* the new captures, mark them
  ///    processed, persist, and return.
  /// 3. If no persisted entry exists → collect a live sensor snapshot,
  ///    compose a local entry, enrich with AI, persist, and return.
  Future<BodyBlogEntry> getTodayEntry() async {
    final now = DateTime.now();
    final existing = await _db.loadEntry(now);
    final unprocessed = await _db.loadUnprocessedCapturesForDate(now);

    // ── fast path: today's entry exists and nothing new to add ──
    if (existing != null && unprocessed.isEmpty) {
      return existing;
    }

    // ── incremental update: entry exists + new captures ──
    if (existing != null && unprocessed.isNotEmpty) {
      final updated = await _applyAi(
        now,
        existing,
        null,
        captureOverride: unprocessed,
      );
      await _db.saveEntry(updated);
      await _db.appendVersion(updated, BlogVersionTrigger.incremental);
      await _db.markCapturesProcessed(unprocessed.map((c) => c.id).toList());
      return updated;
    }

    // ── cold start: no entry for today yet ──
    final snapshot = await _collectSnapshot();
    // Persist a capture so the Capture & Patterns pages stay in sync.
    await _createCaptureFromSnapshot(now, snapshot);
    var entry = _compose(now, snapshot);

    // ── SAVE LOCAL DRAFT IMMEDIATELY ──
    // Guarantees today's entry survives even if the AI call times out,
    // the app is killed, or the device loses connectivity. The AI enrichment
    // below will overwrite this draft with richer content when it succeeds.
    await _db.saveEntry(entry);
    await _db.appendVersion(entry, BlogVersionTrigger.draft);

    final enriched = await _applyAi(now, entry, snapshot);
    if (!identical(enriched, entry)) {
      await _db.saveEntry(enriched);
      await _db.appendVersion(enriched, BlogVersionTrigger.aiEnriched);
      entry = enriched;
    }

    // Mark any captures that existed for today as processed.
    final todayCaptures = await _db.loadCapturesForDate(now);
    if (todayCaptures.isNotEmpty) {
      await _db.markCapturesProcessed(todayCaptures.map((c) => c.id).toList());
    }

    return entry;
  }

  /// Force a full refresh of today's entry — collects fresh sensor data,
  /// runs AI with *all* today's captures, and persists.
  ///
  /// Called by the user-facing "refresh" button.
  ///
  /// Optionally pass a [tone] to adjust the narrative personality.
  Future<BodyBlogEntry> refreshTodayEntry({String? tone}) async {
    final now = DateTime.now();
    final snapshot = await _collectSnapshot();
    // Persist a capture so the Capture & Patterns pages stay in sync.
    await _createCaptureFromSnapshot(now, snapshot);
    var entry = _compose(now, snapshot);

    // Preserve existing user note & mood.
    final existing = await _db.loadEntry(now);
    if (existing != null) {
      if (existing.userNote != null) {
        entry = entry.copyWith(userNote: existing.userNote);
      }
      if (existing.userMood != null) {
        entry = entry.copyWith(userMood: existing.userMood);
      }
    }

    // ── SAVE LOCAL DRAFT IMMEDIATELY ──
    // Protects against data loss if the AI call does not complete.
    await _db.saveEntry(entry);
    await _db.appendVersion(entry, BlogVersionTrigger.draft);

    final enriched = await _applyAi(now, entry, snapshot, tone: tone);
    if (!identical(enriched, entry)) {
      entry = enriched;
      await _db.saveEntry(entry);
      await _db.appendVersion(entry, BlogVersionTrigger.refresh);
    }

    // Mark every capture for today as processed.
    final todayCaptures = await _db.loadCapturesForDate(now);
    if (todayCaptures.isNotEmpty) {
      await _db.markCapturesProcessed(todayCaptures.map((c) => c.id).toList());
    }

    return entry;
  }

  /// Force-regenerate a journal entry with AI for [date].
  ///
  /// **Only allowed for today.** Past entries are locked — their AI-generated
  /// headline / summary / body are immutable once the day has elapsed.
  /// Only the user's own note / mood (via [saveUserNote]) may change a past
  /// entry. Calling this for a past date returns the existing entry unchanged.
  ///
  /// Returns `null` when there is no stored entry for the given date.
  Future<BodyBlogEntry?> regenerateWithAi(DateTime date) async {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    // Past entries are locked — return as-is, no AI call, no DB write.
    if (!isToday) {
      return _db.loadEntry(date);
    }

    // Today: refresh sensors + AI.
    final snapshot = await _collectSnapshot();
    await _createCaptureFromSnapshot(today, snapshot);
    BodyBlogEntry base = _compose(today, snapshot);
    final existing = await _db.loadEntry(today);
    if (existing != null) {
      if (existing.userNote != null) {
        base = base.copyWith(userNote: existing.userNote);
      }
      if (existing.userMood != null) {
        base = base.copyWith(userMood: existing.userMood);
      }
    }

    // Save local draft first so the entry survives if AI times out.
    await _db.saveEntry(base);
    await _db.appendVersion(base, BlogVersionTrigger.draft);

    final updated = await _applyAi(today, base, snapshot);
    if (!identical(updated, base)) {
      await _db.saveEntry(updated);
      await _db.appendVersion(updated, BlogVersionTrigger.regen);
    }

    // Mark all captures for today as processed.
    final captures = await _db.loadCapturesForDate(today);
    if (captures.isNotEmpty) {
      await _db.markCapturesProcessed(captures.map((c) => c.id).toList());
    }

    return updated;
  }

  /// Build the entry list shown in the journal slider.
  ///
  /// Today is always live-fetched (and persisted).
  /// Past days are loaded from the DB — days with no stored entry are
  /// **skipped entirely** rather than injected as misleading skeletons.
  /// This prevents gaps in the slider where a real day used to live.
  ///
  /// [days] is the look-back window; the returned list may be shorter when
  /// some days in that window have no data yet.
  Future<List<BodyBlogEntry>> getRecentEntries({int days = 7}) async {
    final today = DateTime.now();
    final entries = <BodyBlogEntry>[];

    // Today – live data (also persists immediately, before any AI call)
    entries.add(await getTodayEntry());

    // Previous days – only include days that are actually stored in the DB.
    // A null result means the day was never logged (or data was lost before
    // the save-before-AI fix landed); we leave those days out of the slider
    // so the user never sees a confusing empty placeholder for a real day.
    for (var i = 1; i < days; i++) {
      final date = today.subtract(Duration(days: i));
      final stored = await _db.loadEntry(date);
      if (stored != null) entries.add(stored);
    }

    return entries;
  }

  /// Persist or clear a user-written note and mood for [date].
  /// Returns the updated entry, or `null` when the entry is not in the DB
  /// (e.g. the date was never fetched).
  Future<BodyBlogEntry?> saveUserNote(
    DateTime date,
    String? note, {
    String? mood,
  }) {
    return _db.updateUserNote(date, note, mood: mood);
  }

  /// Return all saved version snapshots for [date], newest first.
  ///
  /// Returns an empty list for days recorded before the time-machine feature
  /// was added (schema v8).
  Future<List<BodyBlogVersion>> loadVersionsForDate(DateTime date) =>
      _db.loadVersionsForDate(date);

  // ── capture bridge ──────────────────────────────────────────────

  /// Create and persist a [CaptureEntry] from a live [BodySnapshot].
  ///
  /// This keeps the captures table in sync with every journal generation
  /// so the Capture page, Patterns page, and debug panel all see the data.
  Future<void> _createCaptureFromSnapshot(
    DateTime timestamp,
    BodySnapshot s,
  ) async {
    final id = 'capture_${timestamp.millisecondsSinceEpoch}';
    final capture = CaptureEntry(
      id: id,
      timestamp: timestamp,
      healthData:
          (s.steps > 0 ||
              s.caloriesBurned > 0 ||
              s.avgHeartRate > 0 ||
              s.sleepHours > 0 ||
              s.workouts > 0)
          ? CaptureHealthData(
              steps: s.steps > 0 ? s.steps : null,
              calories: s.caloriesBurned > 0 ? s.caloriesBurned : null,
              distance: s.distanceKm > 0 ? s.distanceKm * 1000 : null,
              heartRate: s.avgHeartRate > 0 ? s.avgHeartRate : null,
              sleepHours: s.sleepHours > 0 ? s.sleepHours : null,
              workouts: s.workouts > 0 ? s.workouts : null,
            )
          : null,
      environmentData: s.temperatureC != null
          ? CaptureEnvironmentData(
              temperature: s.temperatureC,
              aqi: s.aqiUs,
              uvIndex: s.uvIndex,
              weatherDescription: s.weatherDesc,
            )
          : null,
      calendarEvents: s.calendarEvents,
      source: CaptureSource.manual,
      trigger: CaptureTrigger.manual,
    );
    await _db.saveCapture(capture);
  }

  // ── AI enrichment ────────────────────────────────────────────────

  /// Try to enrich [entry] with AI. Returns the updated entry on success,
  /// or the original [entry] unchanged when AI is unavailable.
  ///
  /// When [captureOverride] is provided, those captures are sent to the AI
  /// instead of loading all captures for the date (used for incremental
  /// updates with only the new unprocessed captures).
  ///
  /// Optionally pass a [tone] to adjust the narrative personality.
  Future<BodyBlogEntry> _applyAi(
    DateTime date,
    BodyBlogEntry entry,
    BodySnapshot? snapshotFallback, {
    List<CaptureEntry>? captureOverride,
    String? tone,
  }) async {
    try {
      final captures =
          captureOverride ??
          await _db
              .loadCapturesForDate(date)
              .timeout(const Duration(seconds: 5), onTimeout: () => []);

      final result = await _ai
          .generate(
            date,
            captures,
            snapshotFallback: snapshotFallback,
            userNote: entry.userNote,
            userMood: entry.userMood,
            tone: tone,
          )
          .timeout(const Duration(seconds: 45));

      if (result == null) return entry;

      return entry.copyWith(
        headline: result.headline,
        summary: result.summary,
        fullBody: result.fullBody,
        mood: result.mood,
        moodEmoji: result.moodEmoji,
        tags: result.tags,
        aiGenerated: true,
      );
    } catch (e, st) {
      debugPrint('[BodyBlogService] AI enrichment failed: $e');
      debugPrint('$st');
      return entry;
    }
  }

  // ── data collection ─────────────────────────────────────────────

  Future<BodySnapshot> _collectSnapshot() async {
    int steps = 0;
    double cals = 0;
    double dist = 0;
    double sleep = 0;
    int hr = 0;
    int restingHr = 0;
    double? hrv;
    int workouts = 0;

    try {
      steps = await _health.getTodaySteps().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      cals = await _health.getTodayCalories().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      dist = await _health.getTodayDistance().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      sleep = await _health.getLastNightSleep().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      hr = await _health.getTodayAverageHeartRate().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      restingHr = await _health.getTodayRestingHeartRate().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      hrv = await _health.getTodayHrv().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (_) {}
    try {
      workouts = await _health.getTodayWorkoutCount().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    } catch (_) {}

    // Location + environment
    double? tempC;
    int? aqi;
    double? uv;
    String? weatherDesc;
    String? city;
    try {
      final pos = await _location.getCurrentLocation().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (pos != null) {
        final env = await _ambient
            .scanByCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (env != null) {
          tempC = env.temperature.currentC;
          aqi = env.airQuality.usAqi;
          uv = env.uvIndex.current;
          weatherDesc = env.conditions.description;
          city = env.meta.city;
        }
      }
    } catch (_) {}

    // Calendar
    final calEvents = <String>[];
    try {
      final hasPerm = await _calendar.hasPermissions().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (hasPerm) {
        final events = await _calendar.getTodayEvents().timeout(
          const Duration(seconds: 5),
          onTimeout: () => <Event>[],
        );
        for (final e in events) {
          if (e.title != null && e.title!.isNotEmpty) {
            calEvents.add(e.title!);
          }
        }
      }
    } catch (_) {}

    return BodySnapshot(
      steps: steps,
      caloriesBurned: cals,
      distanceKm: dist / 1000,
      sleepHours: sleep,
      avgHeartRate: hr,
      restingHeartRate: restingHr,
      hrv: hrv,
      workouts: workouts,
      temperatureC: tempC,
      aqiUs: aqi,
      uvIndex: uv,
      weatherDesc: weatherDesc,
      city: city,
      calendarEvents: calEvents,
    );
  }

  // ── narrative composition (local v1 — LLM-ready) ───────────────

  BodyBlogEntry _compose(DateTime date, BodySnapshot s) {
    final mood = _inferMood(s);
    final moodEmoji = _moodEmoji(mood);
    final tags = _buildTags(s);

    final headline = _buildHeadline(s, mood);
    final summary = _buildSummary(s, mood);
    final body = _buildBody(s, mood);

    return BodyBlogEntry(
      date: date,
      headline: headline,
      summary: summary,
      fullBody: body,
      mood: mood,
      moodEmoji: moodEmoji,
      tags: tags,
      snapshot: s,
    );
  }

  // ── mood inference ──────────────────────────────────────────────

  String _inferMood(BodySnapshot s) {
    // Simple heuristic; replace with ML / LLM later
    if (s.sleepHours >= 7 && s.steps >= 5000 && s.avgHeartRate > 0) {
      return 'energised';
    }
    if (s.sleepHours < 5 && s.sleepHours > 0) return 'tired';
    if (s.steps >= 8000) return 'active';
    if (s.aqiUs != null && s.aqiUs! > 100) return 'cautious';
    if (s.sleepHours >= 7) return 'rested';
    if (s.steps == 0 && s.caloriesBurned == 0) return 'quiet';
    return 'calm';
  }

  String _moodEmoji(String mood) {
    switch (mood) {
      case 'energised':
        return '⚡';
      case 'tired':
        return '😴';
      case 'active':
        return '🏃';
      case 'cautious':
        return '🌫️';
      case 'rested':
        return '🧘';
      case 'quiet':
        return '🌙';
      default:
        return '🌿';
    }
  }

  List<String> _buildTags(BodySnapshot s) {
    final tags = <String>[];
    if (s.steps > 0) tags.add('${s.steps} steps');
    if (s.sleepHours > 0) tags.add('${s.sleepHours.toStringAsFixed(1)}h sleep');
    if (s.avgHeartRate > 0) tags.add('${s.avgHeartRate} bpm');
    if (s.temperatureC != null) {
      tags.add('${s.temperatureC!.toStringAsFixed(0)}°C');
    }
    if (s.weatherDesc != null && s.weatherDesc!.isNotEmpty) {
      tags.add(s.weatherDesc!);
    }
    if (s.calendarEvents.isNotEmpty) {
      tags.add('${s.calendarEvents.length} events');
    }
    return tags;
  }

  // ── headline ────────────────────────────────────────────────────

  String _buildHeadline(BodySnapshot s, String mood) {
    // Raw-data headline — no editorial spin. AI will replace this.
    final hasSleep = s.sleepHours > 0;
    final hasSteps = s.steps > 0;
    if (hasSleep && hasSteps) {
      return '${s.sleepHours.toStringAsFixed(1)}h sleep · ${s.steps} steps';
    }
    if (hasSteps) return '${s.steps} steps logged';
    if (hasSleep) return '${s.sleepHours.toStringAsFixed(1)} hours of sleep';
    if (s.avgHeartRate > 0) return '${s.avgHeartRate} bpm avg heart rate';
    if (s.caloriesBurned > 0) {
      return '${s.caloriesBurned.toStringAsFixed(0)} kcal burned';
    }
    return 'No health data collected yet';
  }

  // ── summary (raw data, no editorial) ─────────────────────────────────────

  String _buildSummary(BodySnapshot s, String mood) {
    // Factual data only — AI will replace with an interpreted narrative.
    final parts = <String>[];
    if (s.sleepHours > 0) {
      parts.add('${s.sleepHours.toStringAsFixed(1)}h sleep');
    }
    if (s.steps > 0) parts.add('${s.steps} steps');
    if (s.distanceKm > 0) parts.add('${s.distanceKm.toStringAsFixed(1)} km');
    if (s.avgHeartRate > 0) parts.add('${s.avgHeartRate} bpm');
    if (s.caloriesBurned > 0) {
      parts.add('${s.caloriesBurned.toStringAsFixed(0)} kcal');
    }
    if (s.workouts > 0) {
      parts.add('${s.workouts} workout${s.workouts > 1 ? 's' : ''}');
    }
    if (s.weatherDesc != null && s.city != null) {
      parts.add(
        '${s.city}: ${s.weatherDesc}, ${s.temperatureC?.toStringAsFixed(0) ?? '—'}°C',
      );
    } else if (s.temperatureC != null) {
      parts.add('${s.temperatureC!.toStringAsFixed(0)}°C');
    }
    if (s.aqiUs != null) parts.add('AQI ${s.aqiUs}');

    if (parts.isEmpty) {
      return 'No health data available. Grant health permissions to start tracking.';
    }
    return parts.join(' · ');
  }

  // ── full body ────────────────────────────────────────────────────

  // Returns empty string — the detail view shows a pending-AI panel
  // until the AI fills in the narrative.
  String _buildBody(BodySnapshot s, String mood) => '';
}
