import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';

import '../models/body_blog_entry.dart';
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

    final enriched = await _applyAi(now, entry, snapshot);
    if (!identical(enriched, entry)) {
      await _db.saveEntry(enriched);
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
  Future<BodyBlogEntry> refreshTodayEntry() async {
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

    final enriched = await _applyAi(now, entry, snapshot);
    if (!identical(enriched, entry)) {
      entry = enriched;
      await _db.saveEntry(entry);
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

    final updated = await _applyAi(today, base, snapshot);
    if (!identical(updated, base)) {
      await _db.saveEntry(updated);
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
  Future<BodyBlogEntry> _applyAi(
    DateTime date,
    BodyBlogEntry entry,
    BodySnapshot? snapshotFallback, {
    List<CaptureEntry>? captureOverride,
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

  BodyBlogEntry _composeEmpty(DateTime date) {
    return BodyBlogEntry(
      date: date,
      headline: 'Waiting for data…',
      summary: 'This day\'s journal will appear once data is synced.',
      fullBody: '',
      mood: 'neutral',
      moodEmoji: '🌿',
      tags: const [],
      snapshot: const BodySnapshot(),
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
    switch (mood) {
      case 'energised':
        return 'Your body is buzzing with energy today';
      case 'tired':
        return 'A gentle start — your body is asking for rest';
      case 'active':
        return 'On the move — your body is loving the motion';
      case 'cautious':
        return 'The air outside needs your attention';
      case 'rested':
        return 'Well-rested — a calm canvas for the day';
      case 'quiet':
        return 'A still morning — your body is listening';
      default:
        return 'Your body speaks — a moment of awareness';
    }
  }

  // ── summary (2-3 sentences) ─────────────────────────────────────

  String _buildSummary(BodySnapshot s, String mood) {
    final parts = <String>[];

    // Sleep
    if (s.sleepHours > 0) {
      if (s.sleepHours >= 7) {
        parts.add(
          'You got ${s.sleepHours.toStringAsFixed(1)} hours of sleep — your body feels recharged.',
        );
      } else if (s.sleepHours >= 5) {
        parts.add(
          '${s.sleepHours.toStringAsFixed(1)} hours of sleep. Decent, but your body wouldn\'t mind a bit more.',
        );
      } else {
        parts.add(
          'Only ${s.sleepHours.toStringAsFixed(1)} hours of sleep. Your body is flagging this — consider resting early tonight.',
        );
      }
    }

    // Activity
    if (s.steps > 0) {
      if (s.steps >= 8000) {
        parts.add(
          '${s.steps} steps so far — your muscles are grateful for the movement.',
        );
      } else if (s.steps >= 3000) {
        parts.add(
          '${s.steps} steps and counting. A steady rhythm your body appreciates.',
        );
      } else {
        parts.add(
          '${s.steps} steps today. Even small movements matter — your joints agree.',
        );
      }
    }

    // Environment
    if (s.weatherDesc != null && s.city != null) {
      parts.add(
        'Outside in ${s.city}: ${s.weatherDesc}, ${s.temperatureC?.toStringAsFixed(0) ?? '-'}°C.',
      );
    }

    if (parts.isEmpty) {
      parts.add('Your body is present. Data will fill in as the day unfolds.');
    }

    return parts.join(' ');
  }

  // ── full body (long-form narrative) ─────────────────────────────

  String _buildBody(BodySnapshot s, String mood) {
    final buf = StringBuffer();

    // Sleep section
    if (s.sleepHours > 0) {
      buf.writeln('— Sleep —');
      if (s.sleepHours >= 7) {
        buf.writeln(
          'Last night you gave me ${s.sleepHours.toStringAsFixed(1)} hours of rest. '
          'My cells are humming with recovery. Muscles rebuilt, memories '
          'consolidated, immune defences topped up. Thank you.',
        );
      } else {
        buf.writeln(
          'I only got ${s.sleepHours.toStringAsFixed(1)} hours last night. '
          'I can feel the deficit — cortisol is a touch higher, focus may '
          'wander. If you can, a 20-minute nap today would be a gift.',
        );
      }
      buf.writeln();
    }

    // Movement section
    if (s.steps > 0 || s.caloriesBurned > 0) {
      buf.writeln('— Movement —');
      if (s.steps > 0) {
        buf.writeln(
          'So far: ${s.steps} steps, ${s.distanceKm.toStringAsFixed(1)} km. ',
        );
      }
      if (s.caloriesBurned > 0) {
        buf.writeln(
          'Energy spent: ${s.caloriesBurned.toStringAsFixed(0)} kcal. ',
        );
      }
      if (s.workouts > 0) {
        buf.writeln(
          'I registered ${s.workouts} workout${s.workouts > 1 ? 's' : ''} today — well done.',
        );
      }
      buf.writeln(
        'Every step sends oxygen through me, feeds the brain, nudges '
        'the lymphatic system awake. Keep it up.',
      );
      buf.writeln();
    }

    // Heart
    if (s.avgHeartRate > 0) {
      buf.writeln('— Heart —');
      buf.writeln('Average heart rate today: ${s.avgHeartRate} bpm. ');
      if (s.avgHeartRate < 70) {
        buf.writeln('Calm and steady — a sign of good cardiovascular fitness.');
      } else if (s.avgHeartRate < 90) {
        buf.writeln('Normal range. Your ticker is doing just fine.');
      } else {
        buf.writeln(
          'A bit elevated. Could be exertion, stress, or caffeine — '
          'I\'ll keep monitoring.',
        );
      }
      buf.writeln();
    }

    // Environment
    if (s.weatherDesc != null) {
      buf.writeln('— Environment —');
      buf.write(
        '${s.city != null ? 'In ${s.city}' : 'Your area'}: '
        '${s.weatherDesc}, ${s.temperatureC?.toStringAsFixed(0) ?? '-'}°C.',
      );
      if (s.aqiUs != null) {
        buf.write(' Air quality index: ${s.aqiUs}.');
        if (s.aqiUs! > 100) {
          buf.write(
            ' That\'s moderate-to-poor — consider limiting outdoor exertion.',
          );
        }
      }
      if (s.uvIndex != null && s.uvIndex! > 5) {
        buf.write(
          ' UV is ${s.uvIndex!.toStringAsFixed(1)} — sunscreen advised.',
        );
      }
      buf.writeln();
      buf.writeln();
    }

    // Calendar
    if (s.calendarEvents.isNotEmpty) {
      buf.writeln('— Your Agenda —');
      buf.writeln(
        'You have ${s.calendarEvents.length} event${s.calendarEvents.length > 1 ? 's' : ''} today:',
      );
      for (final ev in s.calendarEvents) {
        buf.writeln('  • $ev');
      }
      buf.writeln(
        '\nRemember to breathe between commitments. I do better when '
        'you take micro-breaks.',
      );
      buf.writeln();
    }

    // Closing
    buf.writeln('—');
    buf.writeln('Stay present. I\'m always here, listening.');
    buf.writeln('\nYour Body');

    return buf.toString();
  }
}
