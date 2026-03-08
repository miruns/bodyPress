# TEST AI — BodyPress Prompt Benchmark

## Current Ranking — Test 1 (Capture Metadata)

| Rank | Model                              | energy_level | body_signal    | location    | stress | themes                 | notable_signals         | Verdict                  |
| ---- | ---------------------------------- | ------------ | -------------- | ----------- | ------ | ---------------------- | ----------------------- | ------------------------ |
| 1    | **llama-3.3-70b-versatile** (Groq) | medium ✅    | well-rested ✅ | home ✅     | 2 ✅   | has premature "social" | specific + cites values | Best judgment            |
| 2    | gpt-oss-120b (OpenAI)              | low ❌       | calm ⚠️        | outdoors ❌ | 3 ⚠️   | has premature "social" | specific + cites values | Good detail, wrong calls |
| 3    | llama-4-scout-17b-16e              | medium ✅    | well-rested ✅ | home ✅     | 2 ✅   | drops "social" ✅      | vague, misses HRV ❌    | Valid but thin           |

> All three produce valid JSON with no wrapper. Enum compliance is clean across the board.

---

Copy-paste the **System Prompt** and **User Prompt** for each test into the AI playground.
Set the listed temperature and max tokens. Paste the raw output under Results.

---

## TEST 1 — Capture Metadata (JSON)

**Temperature: 0.3 · Max tokens: 600**

### System Prompt

```
You are a holistic body-data analyst specializing in longitudinal wellness patterns. You receive biometric and contextual snapshots and return structured JSON optimized for multi-day correlation analysis. Focus on identifying CORRELABLE patterns: how time-of-day, day-type, location, weather, and activities relate to wellness outcomes. Always respond with ONLY the JSON object, no markdown fences, no commentary.
```

### User Prompt

```
Analyse this body/context capture and return structured JSON metadata optimized for MULTI-DAY PATTERN CORRELATION.

Your goal: Generate metadata that enables discovering patterns like:
  - "Mornings after poor sleep correlate with low energy"
  - "Outdoor activity on weekends boosts mood"
  - "High stress on Mondays correlates with work location"
  - "Weather impacts energy levels"

═══ TEMPORAL CONTEXT ═══
• Timestamp   : 2026-03-08T07:42:00
• Time of day : morning (7:00)
• Day         : Sunday (weekend)
• Season      : spring

═══ USER INPUT ═══
• Mood emoji : 😊
• Note : Felt surprisingly good after yesterday's long run

═══ HEALTH METRICS ═══
• Steps      : 1247 (low activity)
• Heart rate : 58 bpm (resting)
• Sleep      : 7.4 hours (good)
• Calories   : 312 kcal
• Distance   : 0.9 km

═══ LIVE BLE HEART RATE SESSION ═══
This is a continuous recording from a BLE chest strap / HR monitor,
captured in real time while the user held the shutter.

• Device       : Polar H10
• Duration     : 4m 12s (48 readings)
• BPM range    : min 54 / avg 58 / max 63
• BPM trend    : stable

HRV (from 46 RR intervals):
  RMSSD : 62.3 ms  → relaxed
  SDNN  : 58.1 ms
  Mean RR: 1034 ms  (= ~58 bpm avg from RR)

HR STORY (use this as narrative context for ai):
  BPM started at 56, averaged 58, peaked at 63, settled to 55 bpm. Overall trend: stable. Autonomic tone: relaxed (RMSSD 62.3 ms).

═══ ENVIRONMENT ═══
• Temperature : 6°C (cold)
• Conditions  : partly cloudy
• Air quality : 38 AQI (good)
• UV index    : 1 (low)
• Humidity    : 72%

═══ LOCATION ═══
• City    : Montréal
• Region  : Québec
• Country : Canada
(Infer location_context: home/work/gym/outdoors/transit/social/other)

═══ CALENDAR ═══
• Events: 09:00 Team standup (30 min), 12:30 Lunch with Sarah
(Consider: Do these events suggest work, social, or personal time?)

═══ CAPTURE INFO ═══
• Source  : manual
• Trigger : userInitiated
• Battery : 87%

═══ REQUIRED OUTPUT ═══
Return ONLY valid JSON with this exact structure:
{
  "summary": "<one sentence describing this moment>",
  "themes": ["<2-4 themes like: recovery, productive, stress, active, relaxed, social, focused>"],
  "energy_level": "<high|medium|low>",
  "mood_assessment": "<brief mood description>",
  "tags": ["<3-5 searchable tags>"],
  "notable_signals": ["<any significant health/environment signals>"],

  "time_of_day": "<early-morning|morning|midday|afternoon|evening|night|late-night>",
  "day_type": "<weekday|weekend>",
  "activity_category": "<active|light-activity|sedentary|recovering|sleeping>",
  "location_context": "<home|work|gym|outdoors|transit|social|other>",
  "sleep_quality": <1-10 or null if no sleep data>,
  "stress_level": <1-10 based on all signals>,
  "weather_impact": "<positive|neutral|negative>",
  "social_context": "<alone|with-others|unknown>",
  "body_signal": "<primary body state: well-rested|fatigued|energized|recovering|stressed|calm>",
  "environment_score": <1-10 based on AQI, UV, weather>,
  "pattern_hints": ["<2-3 correlation hypotheses like: post-workout-energy, weekday-stress, weather-mood-link>"],
  "hrv_context": "<null, or a brief interpretation of the HRV/HR data: e.g. relaxed-autonomic-tone, pre-exertion-elevated, post-workout-recovery>",
  "hr_arc": "<null, or one sentence describing the BPM story: trend, notable spikes, what it may suggest>"
}
```

### Results

#### Model: openai/gpt-oss-120b

```json
{
  "summary": "User feels upbeat on a cool Sunday morning after a long run, showing rested heart rate and good sleep.",
  "themes": ["relaxed", "recovery", "social", "productive"],
  "energy_level": "low",
  "mood_assessment": "Positive and upbeat",
  "tags": ["sunday", "morning", "good-mood", "cold-weather", "post-run"],
  "notable_signals": [
    "low resting heart rate (58 bpm)",
    "high HRV (RMSSD 62.3 ms)",
    "cold temperature (6°C)",
    "low step count (1247)"
  ],
  "time_of_day": "morning",
  "day_type": "weekend",
  "activity_category": "light-activity",
  "location_context": "outdoors",
  "sleep_quality": 8,
  "stress_level": 3,
  "weather_impact": "neutral",
  "social_context": "alone",
  "body_signal": "calm",
  "environment_score": 7,
  "pattern_hints": [
    "post-run-morning-energy",
    "cold-weather-calming-effect",
    "weekend-relaxed-mood"
  ],
  "hrv_context": "relaxed-autonomic-tone",
  "hr_arc": "stable low heart rate with a brief peak at 63 bpm, overall relaxed"
}
```

**Quick assessment:**

- Valid JSON: YES
- No wrapper/preamble: YES
- Enum compliance: YES (all values match allowed enums)
- Factual grounding: MOSTLY — says "low resting heart rate (58 bpm)" but 58 is the HR, resting HR is 56; `location_context: "outdoors"` is debatable (7 AM Sunday at home is more likely `"home"`)
- Insight quality: GOOD — pattern_hints are relevant; hrv_context and hr_arc are concise
- Nitpicks:
  - `energy_level: "low"` feels off — user said "felt surprisingly good", mood is 😊, HRV is high → `"medium"` would fit better
  - `social: "alone"` is reasonable for the capture moment, but calendar has lunch with Sarah → `"unknown"` might be safer
  - `"social"` in themes is premature — the capture itself is a solo morning moment

#### Model: llama-3.3-70b-versatile (Groq)

```json
{
  "summary": "User feels upbeat on a cool Sunday morning after a long run, showing rested heart rate and good sleep.",
  "themes": ["relaxed", "recovery", "social", "productive"],
  "energy_level": "medium",
  "mood_assessment": "Feeling good and calm",
  "tags": ["sunday", "morning", "good-mood", "cold-weather", "post-run"],
  "notable_signals": [
    "low resting heart rate (58 bpm)",
    "high HRV (RMSSD 62.3 ms)",
    "cold temperature (6°C)",
    "good sleep quality (7.4 hours)"
  ],
  "time_of_day": "morning",
  "day_type": "weekend",
  "activity_category": "light-activity",
  "location_context": "home",
  "sleep_quality": 8,
  "stress_level": 2,
  "weather_impact": "neutral",
  "social_context": "alone",
  "body_signal": "well-rested",
  "environment_score": 7,
  "pattern_hints": [
    "post-run-morning-energy",
    "weekend-relaxed-mood",
    "good-sleep-mood-link"
  ],
  "hrv_context": "relaxed-autonomic-tone",
  "hr_arc": "stable low heart rate with a brief peak at 63 bpm, indicating a calm and rested state"
}
```

**Quick assessment:**

- Valid JSON: YES
- No wrapper/preamble: YES
- Enum compliance: YES
- Factual grounding: GOOD — same 58 bpm mislabel as GPT-oss, but correctly picks `location_context: "home"` (better than GPT-oss's "outdoors")
- Insight quality: GOOD — `good-sleep-mood-link` is a better pattern hint than GPT-oss's `cold-weather-calming-effect`
- Improvements over gpt-oss-120b:
  - `energy_level: "medium"` — correct, matches 😊 mood + high HRV + "felt surprisingly good"
  - `body_signal: "well-rested"` — better fit than "calm" given 7.4h sleep + positive note
  - `location_context: "home"` — more logical for 7 AM Sunday
  - `stress_level: 2` — slightly better than 3 given relaxed HRV
- Same nitpick: `"social"` in themes is still premature for the capture moment

#### Model: meta-llama/llama-4-scout-17b-16e-instruct

```json
{
  "summary": "User felt surprisingly good on a Sunday morning after a long run, with good sleep and low activity",
  "themes": ["recovery", "relaxed", "active"],
  "energy_level": "medium",
  "mood_assessment": "positive",
  "tags": ["Sunday", "morning", "post-workout"],
  "notable_signals": ["good sleep", "low activity", "stable heart rate"],
  "time_of_day": "morning",
  "day_type": "weekend",
  "activity_category": "sedentary",
  "location_context": "home",
  "sleep_quality": 8,
  "stress_level": 2,
  "weather_impact": "neutral",
  "social_context": "alone",
  "body_signal": "well-rested",
  "environment_score": 8,
  "pattern_hints": [
    "post-workout-energy",
    "weekend-recovery",
    "sleep-mood-link"
  ],
  "hrv_context": "relaxed-autonomic-tone",
  "hr_arc": "stable heart rate with a slight increase to 63 bpm"
}
```

**Quick assessment:**

- Valid JSON: YES
- No wrapper/preamble: YES
- Enum compliance: YES
- Factual grounding: OK — no number mislabeling, but `notable_signals` are vague ("good sleep", "low activity") rather than citing actual values
- Insight quality: DECENT but thinner
- Compared to the other two:
  - Drops `"social"` from themes — **good**, more accurate for a solo morning
  - `activity_category: "sedentary"` — **wrong**, user walked 0.9 km + 1247 steps + wore a chest strap → `"light-activity"` is correct
  - `tags` only 3 items — below the requested 3–5 range, and capitalized (`"Sunday"`) vs lowercase convention
  - `notable_signals` are generic prose instead of specific data points — less useful for pattern correlation
  - `mood_assessment: "positive"` — too terse compared to Llama-70B's "Feeling good and calm"
  - `hr_arc` doesn't mention starting/ending BPM or trend label — loses narrative richness
  - No mention of HRV data in `notable_signals` despite RMSSD 62.3 ms being a standout metric
  - `environment_score: 8` — slightly generous for 6°C cold + cloudy (7 from the others feels more accurate)

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

---

## TEST 2 — Daily Journal (default tone)

**Temperature: 0.72 · Max tokens: 1000**

### System Prompt

```
You are writing someone's daily body journal.
You speak as a warm, wise narrator — the body itself addressing its person.
You weave hard biometric facts (steps, sleep, heart rate, temperature…) into vivid, personal prose.
Tone: intimate, honest, poetic — never clinical, never alarmist.
Never give medical advice. Celebrate movement. Acknowledge fatigue. Find beauty in data.
```

### User Prompt

```
Generate the body journal for Sunday, March 8, 2026.

── PERSONAL INPUT ──
Mood: 😊
Note: "Felt surprisingly good after yesterday's long run"

── 3 DATA CAPTURES (chronological) ──

▸ 7:42 AM
  Health: 1247 steps · 312 kcal · 7.4 h sleep · 58 bpm · 0.90 km
  Environment: 6.0°C · partly cloudy · AQI 38 · UV 1.0 · 72% humidity
  Location: Montréal, Québec, Canada
  Calendar: 09:00 Team standup (30 min) · 12:30 Lunch with Sarah
  Note: "Felt surprisingly good after yesterday's long run"

▸ 12:55 PM
  Health: 5812 steps · 1140 kcal · 72 bpm · 4.20 km
  Environment: 9.0°C · partly cloudy · AQI 42
  Location: Montréal, Québec, Canada

▸ 6:30 PM
  Health: 11340 steps · 2015 kcal · 68 bpm · 8.20 km · 1 workout
  Environment: 4.0°C · clear · AQI 35 · UV 0.0 · 65% humidity
  Location: Montréal, Québec, Canada
  Calendar: 19:00 Yoga class (60 min)
  Note: "Evening run along the canal felt great, legs still fresh"

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
```

### Results

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

---

## TEST 3 — Pattern Narrative (plain text)

**Temperature: 0.75 · Max tokens: 300**

### System Prompt

```
You are writing a short body-pattern narrative for BodyPress — a personal body journal app.
Speak as the body itself, addressing the user in second person ("you").
Be warm, wise, and grounded in the data provided. No fluff.
3–5 sentences maximum. No headings, no bullet points, no markdown.
Highlight the most meaningful pattern or correlation you see.
End with one forward-looking observation or gentle nudge.
```

### User Prompt

```
Here is the user's aggregated body-pattern data:

• 38 of 42 captures analysed.
• Energy breakdown: high 12, medium 19, low 7.
• Top themes: recovery ×21 ↑, outdoor-activity ×18, good-sleep ×16, social ×8 ↓, work-stress ×7.
• Theme–energy correlations: "outdoor-activity" → high energy 78%; "good-sleep" → high energy 64%; "work-stress" → low energy 71%.
• Co-occurring themes: outdoor-activity + good-sleep ×11, work-stress + poor-sleep ×5, recovery + calm ×9, social + energized ×6.
• Peak capture window: morning (14 captures).
• Body signals: well-rested ×13, energized ×10, calm ×7.
• AI-observed patterns: morning-outdoor-boost, sleep-recovery-link, midweek-stress-dip, weekend-energy-peak.
• Recurring signals: elevated resting HR on work-stress days ×5, HRV drop below 40ms on poor-sleep nights ×4.

Write a short narrative (3–5 sentences) that synthesises these patterns. Speak as the body. Be specific — reference the actual themes and data. Plain text only.
```

### Results

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

#### Model: **\*\***\_\_\_**\*\***

```
(paste output here)
```

---

## Comparison

| Model | Test 1 (JSON valid?) | Test 1 quality | Test 2 (JSON valid?) | Test 2 voice/quality | Test 3 format ok? | Test 3 quality | Winner? |
| ----- | -------------------- | -------------- | -------------------- | -------------------- | ----------------- | -------------- | ------- |
|       |                      |                |                      |                      |                   |                |         |
|       |                      |                |                      |                      |                   |                |         |
|       |                      |                |                      |                      |                   |                |         |
