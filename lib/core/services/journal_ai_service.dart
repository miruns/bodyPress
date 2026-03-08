import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/body_blog_entry.dart';
import '../models/capture_entry.dart';
import 'ai_service.dart';

/// The result of an AI-powered journal generation.
class JournalAiResult {
  final String headline;
  final String summary;
  final String fullBody;
  final String mood;
  final String moodEmoji;
  final List<String> tags;

  const JournalAiResult({
    required this.headline,
    required this.summary,
    required this.fullBody,
    required this.mood,
    required this.moodEmoji,
    required this.tags,
  });

  static const _validMoods = {
    'energised',
    'tired',
    'active',
    'cautious',
    'rested',
    'quiet',
    'calm',
  };

  factory JournalAiResult.fromJson(Map<String, dynamic> json) {
    final rawMood = (json['mood'] as String? ?? 'calm').trim().toLowerCase();
    return JournalAiResult(
      headline: json['headline'] as String? ?? 'A day of quiet presence',
      summary: json['summary'] as String? ?? '',
      fullBody: json['full_body'] as String? ?? '',
      mood: _validMoods.contains(rawMood) ? rawMood : 'calm',
      moodEmoji: json['mood_emoji'] as String? ?? '🌿',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((t) => t.toString())
          .toList(),
    );
  }
}

/// Generates AI-powered journal narratives for a given day.
///
/// Uses the day's [CaptureEntry] list as the primary context window.
/// If no captures are available, falls back to a [BodySnapshot] collected
/// live from the device.
///
/// Calls ai.governor-hq.com and expects the model to return clean JSON.
class JournalAiService {
  final AiService _ai;

  JournalAiService({AiService? ai}) : _ai = ai ?? AiService();

  // ── public API ────────────────────────────────────────────────────────────

  /// Generate a daily journal entry for [date].
  ///
  /// Pass [captures] collected throughout the day as primary context.
  /// Optionally pass a [snapshotFallback] (live sensor data) when no
  /// captures are stored yet — it will be used to build a single synthetic
  /// snapshot so the AI still has real data to work with.
  ///
  /// Optionally pass a [tone] to adjust the narrative personality:
  /// - `null` (default): warm, wise narrator
  /// - 'motivational': encouraging, energizing coach
  /// - 'poetic': lyrical, metaphorical, artistic
  /// - 'scientific': precise, analytical, data-focused
  /// - 'humorous': playful, lighthearted, witty
  /// - 'minimalist': concise, direct, zen-like
  ///
  /// Returns `null` if the AI call fails or there is no data at all.
  Future<JournalAiResult?> generate(
    DateTime date,
    List<CaptureEntry> captures, {
    BodySnapshot? snapshotFallback,
    String? userNote,
    String? userMood,
    String? tone,
  }) async {
    final hasCaptures = captures.isNotEmpty;
    final hasSnapshot =
        snapshotFallback != null && _snapshotHasData(snapshotFallback);

    if (!hasCaptures && !hasSnapshot) return null;

    final prompt = hasCaptures
        ? _buildCapturesPrompt(
            date,
            captures,
            userNote: userNote,
            userMood: userMood,
          )
        : _buildSnapshotPrompt(
            date,
            snapshotFallback!,
            userNote: userNote,
            userMood: userMood,
          );

    try {
      final systemPrompt = _buildSystemPrompt(tone);
      final raw = await _ai.ask(
        prompt,
        systemPrompt: systemPrompt,
        temperature: 0.72,
        maxTokens: 1000,
      );
      final cleaned = _stripMarkdownFences(raw.trim());
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final result = JournalAiResult.fromJson(json);

      // Strip tags that reference health metrics the snapshot doesn't have.
      final s = snapshotFallback;
      final hasHealth =
          (s != null &&
              (s.steps > 0 ||
                  s.sleepHours > 0 ||
                  s.avgHeartRate > 0 ||
                  s.caloriesBurned > 0)) ||
          captures.any((c) => c.healthData != null);
      if (!hasHealth) {
        final healthRe = RegExp(
          r'step|sleep|bpm|heart|cardio|calori|kcal|workout|exercise|km\b|mile',
          caseSensitive: false,
        );
        final cleanTags = result.tags
            .where((t) => !healthRe.hasMatch(t))
            .toList();
        return JournalAiResult(
          headline: result.headline,
          summary: result.summary,
          fullBody: result.fullBody,
          mood: result.mood,
          moodEmoji: result.moodEmoji,
          tags: cleanTags,
        );
      }
      return result;
    } catch (e, st) {
      debugPrint('[JournalAiService] generation failed: $e');
      debugPrint('$st');
      return null;
    }
  }

  // ── system prompt ─────────────────────────────────────────────────────────

  static const String _kSystemPrompt = '''
You are writing someone's daily body journal.
You speak as a warm, wise narrator — the body itself addressing its person.
You weave hard biometric facts (steps, sleep, heart rate, temperature…) into vivid, personal prose.
Tone: intimate, honest, poetic — never clinical, never alarmist.
Never give medical advice. Celebrate movement. Acknowledge fatigue. Find beauty in data.
''';

  /// Build a system prompt based on the selected tone.
  /// Returns the default prompt when [tone] is null.
  String _buildSystemPrompt(String? tone) {
    if (tone == null) return _kSystemPrompt;

    switch (tone) {
      case 'motivational':
        return '''
You are writing someone's daily body journal as an encouraging coach.
You speak as the body itself — energizing, uplifting, and celebrating every win.
You weave biometric facts (steps, sleep, heart rate, temperature…) into powerful, motivating prose.
Tone: enthusiastic, supportive, action-oriented — inspire momentum and progress.
Never give medical advice. Celebrate every step forward. Turn challenges into opportunities. Find the victory in data.
''';
      case 'poetic':
        return '''
You are writing someone's daily body journal as a lyrical poet.
You speak as the body itself — crafting metaphors, finding rhythm, painting with words.
You transform biometric facts (steps, sleep, heart rate, temperature…) into artistic, flowing prose.
Tone: metaphorical, lyrical, evocative — like a prose poem celebrating existence.
Never give medical advice. Find beauty in motion. Turn data into verse. See the poetry in being.
''';
      case 'scientific':
        return '''
You are writing someone's daily body journal as a precise analyst.
You speak as the body itself — clear, data-driven, and insightfully analytical.
You present biometric facts (steps, sleep, heart rate, temperature…) with precision and meaningful context.
Tone: analytical, evidence-based, informative — clear patterns and correlations.
Never give medical advice. Present data with clarity. Highlight trends. Find insights in numbers.
''';
      case 'humorous':
        return '''
You are writing someone's daily body journal with a playful spirit.
You speak as the body itself — witty, lighthearted, and finding joy in the journey.
You weave biometric facts (steps, sleep, heart rate, temperature…) into charming, entertaining prose.
Tone: playful, warm, gently funny — make the person smile while staying supportive.
Never give medical advice. Celebrate with humor. Acknowledge struggles lightly. Find the comedy in being human.
''';
      case 'minimalist':
        return '''
You are writing someone's daily body journal with zen simplicity.
You speak as the body itself — concise, clear, present-moment focused.
You distill biometric facts (steps, sleep, heart rate, temperature…) to their essence.
Tone: minimal, direct, centered — every word counts, nothing extra.
Never give medical advice. Be brief. Observe clearly. Find peace in simplicity.
''';
      default:
        return _kSystemPrompt;
    }
  }

  // ── prompt for multiple CaptureEntry objects ──────────────────────────────

  String _buildCapturesPrompt(
    DateTime date,
    List<CaptureEntry> captures, {
    String? userNote,
    String? userMood,
  }) {
    final dateFmt = DateFormat('EEEE, MMMM d, yyyy').format(date);
    final timeFmt = DateFormat('h:mm a');
    final buf = StringBuffer();

    buf.writeln('Generate the body journal for $dateFmt.\n');

    if (userMood != null || userNote != null) {
      buf.writeln('── PERSONAL INPUT ──');
      if (userMood != null) buf.writeln('Mood: $userMood');
      if (userNote != null) buf.writeln('Note: "$userNote"');
      buf.writeln();
    }

    buf.writeln(
      '── ${captures.length} DATA CAPTURE${captures.length > 1 ? 'S' : ''} (chronological) ──\n',
    );

    for (final c in captures) {
      buf.writeln('▸ ${timeFmt.format(c.timestamp)}');

      if (c.healthData != null) {
        final h = c.healthData!;
        final parts = <String>[];
        if ((h.steps ?? 0) > 0) parts.add('${h.steps} steps');
        if ((h.calories ?? 0) > 0) {
          parts.add('${h.calories!.toStringAsFixed(0)} kcal');
        }
        if ((h.sleepHours ?? 0) > 0) {
          parts.add('${h.sleepHours!.toStringAsFixed(1)} h sleep');
        }
        if ((h.heartRate ?? 0) > 0) parts.add('${h.heartRate} bpm');
        if ((h.distance ?? 0) > 0) {
          parts.add('${(h.distance! / 1000).toStringAsFixed(2)} km');
        }
        if ((h.workouts ?? 0) > 0) {
          parts.add('${h.workouts} workout${h.workouts! > 1 ? 's' : ''}');
        }
        if (parts.isNotEmpty) buf.writeln('  Health: ${parts.join(' · ')}');
      }

      if (c.environmentData != null) {
        final e = c.environmentData!;
        final parts = <String>[];
        if (e.temperature != null) {
          parts.add('${e.temperature!.toStringAsFixed(1)}°C');
        }
        if (e.weatherDescription != null && e.weatherDescription!.isNotEmpty) {
          parts.add(e.weatherDescription!);
        }
        if (e.aqi != null) parts.add('AQI ${e.aqi}');
        if (e.uvIndex != null) parts.add('UV ${e.uvIndex!.toStringAsFixed(1)}');
        if (e.humidity != null) parts.add('${e.humidity}% humidity');
        if (parts.isNotEmpty) {
          buf.writeln('  Environment: ${parts.join(' · ')}');
        }
      }

      if (c.locationData != null) {
        final l = c.locationData!;
        final loc = [
          l.city,
          l.region,
          l.country,
        ].whereType<String>().join(', ');
        if (loc.isNotEmpty) buf.writeln('  Location: $loc');
      }

      if (c.calendarEvents.isNotEmpty) {
        buf.writeln('  Calendar: ${c.calendarEvents.join(' · ')}');
      }

      if (c.userNote != null && c.userNote!.isNotEmpty) {
        buf.writeln('  Note: "${c.userNote}"');
      }

      buf.writeln();
    }

    buf.write(_kJsonInstructions);
    return buf.toString();
  }

  // ── prompt for BodySnapshot fallback (no captures yet) ───────────────────

  String _buildSnapshotPrompt(
    DateTime date,
    BodySnapshot s, {
    String? userNote,
    String? userMood,
  }) {
    final dateFmt = DateFormat('EEEE, MMMM d, yyyy').format(date);
    final buf = StringBuffer();

    buf.writeln('Generate the body journal for $dateFmt.\n');

    if (userMood != null || userNote != null) {
      buf.writeln('── PERSONAL INPUT ──');
      if (userMood != null) buf.writeln('Mood: $userMood');
      if (userNote != null) buf.writeln('Note: "$userNote"');
      buf.writeln();
    }

    buf.writeln('── TODAY\'S SNAPSHOT ──\n');

    final healthParts = <String>[];
    if (s.steps > 0) healthParts.add('${s.steps} steps');
    if (s.distanceKm > 0) {
      healthParts.add('${s.distanceKm.toStringAsFixed(1)} km');
    }
    if (s.caloriesBurned > 0) {
      healthParts.add('${s.caloriesBurned.toStringAsFixed(0)} kcal');
    }
    if (s.sleepHours > 0) {
      healthParts.add('${s.sleepHours.toStringAsFixed(1)} h sleep');
    }
    if (s.avgHeartRate > 0) healthParts.add('${s.avgHeartRate} bpm');
    if (s.workouts > 0) {
      healthParts.add('${s.workouts} workout${s.workouts > 1 ? 's' : ''}');
    }
    if (healthParts.isNotEmpty) {
      buf.writeln('  Health: ${healthParts.join(' · ')}');
    }

    final envParts = <String>[];
    if (s.temperatureC != null) {
      envParts.add('${s.temperatureC!.toStringAsFixed(1)}°C');
    }
    if (s.weatherDesc != null && s.weatherDesc!.isNotEmpty) {
      envParts.add(s.weatherDesc!);
    }
    if (s.aqiUs != null) envParts.add('AQI ${s.aqiUs}');
    if (s.uvIndex != null) envParts.add('UV ${s.uvIndex!.toStringAsFixed(1)}');
    if (envParts.isNotEmpty) {
      buf.writeln('  Environment: ${envParts.join(' · ')}');
    }

    if (s.city != null && s.city!.isNotEmpty) {
      buf.writeln('  Location: ${s.city}');
    }

    if (s.calendarEvents.isNotEmpty) {
      buf.writeln('  Calendar: ${s.calendarEvents.join(' · ')}');
    }

    buf.writeln();
    buf.write(_kJsonInstructions);
    return buf.toString();
  }

  // ── shared JSON output spec ───────────────────────────────────────────────

  static const String _kJsonInstructions = '''
Based on the data above, return a single JSON object with EXACTLY these keys:

{
  "headline": "...",
  "summary": "...",
  "full_body": "...",
  "mood": "...",
  "mood_emoji": "...",
  "tags": ["..."]
}

Rules:
- headline: 6–10 words. Vivid, personal to today's data. Not generic.
- summary: 2–3 sentences. The emotional + physical essence of the day.
- full_body: 200–350 words. 3–5 labelled sections. Only include sections for data categories actually present above (e.g. skip — Sleep —, — Heart — if no health data was provided). Body speaks warmly to its person.
- mood: exactly one of: energised, tired, active, cautious, rested, quiet, calm
- mood_emoji: single emoji matching mood
- tags: 4–7 short labels derived ONLY from data actually provided above (e.g. "Clear skies", "18°C", "3 events")

CRITICAL: NEVER invent, estimate, or hallucinate numbers. If no health data (steps, sleep, heart rate, calories) appears above, do NOT mention any health metrics in headline, summary, full_body, or tags. Only reference data explicitly listed above.

Respond with ONLY valid JSON. No markdown fences. No explanation.
''';

  // ── helpers ───────────────────────────────────────────────────────────────

  bool _snapshotHasData(BodySnapshot s) =>
      s.steps > 0 ||
      s.sleepHours > 0 ||
      s.avgHeartRate > 0 ||
      s.caloriesBurned > 0 ||
      s.temperatureC != null;

  /// Strip ```json ... ``` fences that some models still add despite instructions.
  String _stripMarkdownFences(String text) {
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline == -1) return text;
    var inner = text.substring(firstNewline + 1);
    if (inner.endsWith('```')) inner = inner.substring(0, inner.length - 3);
    return inner.trimRight();
  }
}
