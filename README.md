# BodyPress

[![CI — Download Build APK](https://github.com/the-governor-hq/bodyPress-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/the-governor-hq/bodyPress-flutter/actions/workflows/ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.9.2%2B-blue?logo=flutter)
![Version](https://img.shields.io/badge/version-1.0.5-informational)
![License](https://img.shields.io/badge/license-MIT-green)

> Your body writes a journal every day — BodyPress reads it.

A cross-platform Flutter app that collects physiological, environmental, and behavioural signals from device sensors, then synthesises them into a daily first-person narrative: a blog written _by_ your body, _for_ you.

---

## Screenshots

<table>
  <tr>
    <td><img width="200" src="https://github.com/user-attachments/assets/400c148d-80cc-4614-b224-e1b11ff16a29" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/89eb3103-79c0-4b05-8a16-2f077ef2c46b" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/6afd6d98-23a1-4cd2-9c2d-cd3e9c2d3841" /></td>
     <td><img width="200" alt="image" src="https://github.com/user-attachments/assets/39a1ab62-2769-49e0-a195-0bc4d4386df8" /></td>

    <td><img width="200" alt="Journal" src="https://github.com/user-attachments/assets/83c0a31e-1cfe-48e3-9478-9fcbf6c12dcc" /></td>
    <td><img width="200" alt="Capture" src="https://github.com/user-attachments/assets/4a6de629-54b0-40f4-af2a-b8650b305fd2" /></td>
    <td><img width="200" alt="Patterns" src="https://github.com/user-attachments/assets/7b58bd67-4dc1-4cd4-88a7-6a177d931bb1" /></td>
    <td><img width="200" alt="Detail" src="https://github.com/user-attachments/assets/1c07cc5f-6dfd-4f66-9294-19f1bf20e8d8" /></td>
  </tr>
</table>

<details>
<summary>More screenshots</summary>

<table>
  <tr>
    <td><img width="200" src="https://github.com/user-attachments/assets/ecee3855-2836-4e5b-a559-c9edac9166a7" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/4b7bb0b1-2f92-40b1-a170-49a67ac802c8" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/8834a150-3d16-4fcc-bb7f-a184a9b91c48" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/b76caba3-f7ee-449f-ab20-9795bbcff717" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/ce5c09cf-0021-4f67-bb28-31bc0b6fcdfe" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/4f7cb624-64e7-4728-a1d4-ea87a914cf15" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/3218e319-f647-4b30-8785-f6bf38256e6e" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/57cd41ac-3d52-43cf-9cac-da500b8caa3e" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/f44194ea-0f20-4805-8744-a85c1f80f844" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/14dd1b37-20f3-412b-aa8a-8521633e7488" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/d009636a-4713-48a2-b62a-81ec479cc320" /></td>
    <td><img width="200" src="https://github.com/user-attachments/assets/86b6c9a9-30af-4715-a62d-9a62e11e7d16" /></td>
  </tr>
</table>

</details>

---

## Why BodyPress?

Most health apps show dashboards of numbers. BodyPress takes a different approach: it presents your biometrics as a _narrative_. Story-framing surfaces correlations you'd otherwise miss — poor sleep preceding an elevated resting heart rate, high AQI days correlating with fewer steps — and reading about yourself is more engaging than staring at charts.

Under the hood the app treats the human body as an observable system: collect objective signals throughout the day, feed them to an LLM, and get back a warm, first-person journal entry that reads as though your body is writing to you.

---

## Features

| Feature                  | Description                                                                                                                                                                                                                             |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AI Journal**           | Daily narrative generated from real sensor data — headline, mood, summary, full body text. Written in first-person ("your body speaking to you").                                                                                       |
| **Smart Refresh**        | Persisted entries return instantly. AI runs only when new unprocessed captures exist. No redundant sensor reads or API calls.                                                                                                           |
| **Background Captures**  | WorkManager-based periodic data collection with quiet-hour and battery-awareness support.                                                                                                                                               |
| **Manual Capture**       | On-demand snapshot with toggleable data sources (health, environment, location, calendar, BLE HR device).                                                                                                                               |
| **BLE Heart Rate**       | Real-time streaming from any Bluetooth Low Energy Heart Rate Profile (0x180D) device — Polar H10, Wahoo TICKR, Garmin straps, etc. Live ECG-style waveform displayed in the Capture screen. Snapshot BPM auto-attached to each capture. |
| **Cardiovascular Depth** | Resting heart rate and HRV (SDNN) read from HealthKit / Health Connect alongside average HR. All three are included in daily snapshots and AI prompts.                                                                                  |
| **Patterns & Trends**    | AI-derived insights aggregated from capture history — energy distribution, recurring themes, notable signals, recent moments timeline.                                                                                                  |
| **User Annotations**     | Free-text notes and mood emojis per day, persisted in SQLite alongside the AI-generated content.                                                                                                                                        |
| **Onboarding**           | Step-by-step permission flow with per-permission explanations and privacy notes. Every step is skippable.                                                                                                                               |
| **Dark & Light Themes**  | Material 3 theming with system-mode detection.                                                                                                                                                                                          |

---

## Data Sources

| Domain             | Sensor / API                        | What's read                                                |
| ------------------ | ----------------------------------- | ---------------------------------------------------------- |
| **Movement**       | Health Connect / HealthKit          | Steps, distance, calories, workouts                        |
| **Cardiovascular** | Optical HR sensor (OS health store) | Average HR, resting HR, HRV (SDNN)                         |
| **Cardiovascular** | BLE HR strap (direct, 0x180D)       | Live BPM stream + RR intervals — no OS sync needed         |
| **Sleep**          | Device sleep tracking               | Duration, phases                                           |
| **Environment**    | GPS → ambient-scan API              | Temperature, humidity, AQI, UV, pressure, wind, conditions |
| **Schedule**       | Device calendar (CalDAV)            | Today's events                                             |
| **Location**       | GPS (Geolocator)                    | Coordinates — ephemeral, never stored                      |

> **Privacy:** GPS is read once to fetch environmental data, then discarded. No location history is recorded or transmitted. Health data is read-only — the app never writes to HealthKit or Health Connect.

---

## Tech Stack

| Concern          | Library                               | Role                                                                    |
| ---------------- | ------------------------------------- | ----------------------------------------------------------------------- |
| State management | `flutter_riverpod` ^2.6.1             | DI + reactive state                                                     |
| Routing          | `go_router` ^14.6.2                   | Declarative navigation (3-tab shell + standalone routes)                |
| Health           | `health` ^11.1.0                      | Cross-platform HealthKit / Health Connect (HR, resting HR, HRV, steps…) |
| BLE              | `flutter_blue_plus` ^1.35.3           | BLE scan / connect / notify — Heart Rate Profile 0x180D                 |
| Location         | `geolocator` ^13.0.2                  | GPS coordinates                                                         |
| Calendar         | `device_calendar` ^4.3.2              | CalDAV read                                                             |
| HTTP             | `http` ^1.2.2                         | Ambient-scan & AI API calls                                             |
| Persistence      | `sqflite` ^2.3.3 + `path`             | Local SQLite (entries, captures, settings) — schema v7                  |
| Background       | `workmanager` ^0.9.0                  | Periodic background captures                                            |
| Notifications    | `flutter_local_notifications` ^17.0.0 | Daily reminders                                                         |
| Sharing          | `share_plus` ^10.1.0                  | Share journal entries                                                   |
| Typography       | `google_fonts` ^6.2.1                 | Inter (body) / Playfair Display (headlines)                             |
| Formatting       | `intl` ^0.19.0                        | Date/number formatting                                                  |
| Config           | `flutter_dotenv` ^6.0.0               | `.env` file support                                                     |

---

## Getting Started

### Prerequisites

- Flutter SDK **≥ 3.9.2**
- **iOS:** Xcode 14+, deployment target iOS 14+
- **Android:** SDK 21+ (Android 5.0), Health Connect app for health data on Android 13+

### Install & run

```bash
flutter pub get
flutter run

# Or use the helper scripts
.\dev.ps1           # Windows (PowerShell)
./dev.sh            # macOS / Linux
```

### Environment

Copy `.env.example` to `.env` and fill in your API key:

```
AI_API_KEY=your_key_here
```

### Platform configuration

<details>
<summary><strong>iOS</strong></summary>

`Info.plist` keys are pre-configured:

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
- `NSCalendarsUsageDescription`
- `NSMotionUsageDescription`
- `NSBluetoothAlwaysUsageDescription` ← BLE heart rate devices
- `NSBluetoothPeripheralUsageDescription`

Enable HealthKit capability in Xcode: **Runner** target → **Signing & Capabilities** → **+ HealthKit**.

</details>

<details>
<summary><strong>Android</strong></summary>

`AndroidManifest.xml` includes permissions for location, Health Connect (including `READ_HEART_RATE_VARIABILITY`), activity recognition, calendar, and BLE:

- `BLUETOOTH` / `BLUETOOTH_ADMIN` (API ≤ 30 legacy)
- `BLUETOOTH_SCAN` (`neverForLocation`) + `BLUETOOTH_CONNECT` (API 31+)
- `android.hardware.bluetooth_le` feature declaration (`required=false` — app installs on non-BLE devices)

The Health Connect app is required on Android 13+ for HR, resting HR, and HRV data.

</details>

---

## Architecture

```
lib/
├── core/
│   ├── background/           # WorkManager callback (capture_executor.dart)
│   ├── models/               # Immutable domain objects
│   │   ├── body_blog_entry   #   BodyBlogEntry + BodySnapshot
│   │   ├── capture_entry     #   CaptureEntry + health/env/location sub-models
│   │   ├── capture_ai_metadata  # AI-derived tags, themes, energy level per capture
│   │   ├── ai_models         #   ChatMessage, request/response DTOs
│   │   └── background_capture_config
│   ├── router/               # GoRouter (3-tab shell + standalone routes)
│   ├── services/             # All business logic
│   │   ├── service_providers #   ★ Central Riverpod provider registry
│   │   ├── body_blog_service #   Smart-refresh orchestrator
│   │   ├── journal_ai_service  # Prompt → AI → JournalAiResult
│   │   ├── capture_metadata_service  # Per-capture background AI metadata
│   │   ├── ai_service        #   HTTP client for ai.governor-hq.com
│   │   ├── local_db_service  #   SQLite CRUD (schema v7)
│   │   ├── capture_service   #   Multi-source data → CaptureEntry
│   │   ├── background_capture_service  # WorkManager scheduler
│   │   ├── context_window_service  # 7-day rolling context builder
│   │   ├── health_service    #   HealthKit / Health Connect (HR, resting HR, HRV)
│   │   ├── ble_heart_rate_service  # BLE 0x180D scan/connect/stream + RR parsing
│   │   ├── location_service  #   Geolocator wrapper
│   │   ├── ambient_scan_service  # Environment API
│   │   ├── gps_metrics_service   # Real-time GPS metrics
│   │   ├── calendar_service  #   Device calendar read
│   │   ├── notification_service  # Local notification scheduling
│   │   └── permission_service    # Permission orchestration
│   ├── widgets/              # Shared low-level widgets
│   │   └── live_hr_waveform  #   60 fps ECG-style PQRST waveform (BLE)
│   └── theme/                # Material 3 (light + dark)
├── features/
│   ├── onboarding/           # Step-by-step permission flow
│   ├── journal/              # Journal tab — paginated daily narrative
│   ├── body_blog/            # Blog screen & widgets (detail, cards, AI badge)
│   ├── patterns/             # AI-derived trends & insights
│   ├── capture/              # Manual capture with data-source toggles
│   ├── shell/                # AppShell (3-tab nav) + DebugScreen
│   ├── environment/          # Detailed environment view
│   ├── shared/               # Reusable widgets
│   └── …                     # health, location, calendar, ai_test, permissions
└── main.dart                 # App entry point
```

### Key Domain Types

| Type                | Purpose                                                                                                                                                                                                                            |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BodyBlogEntry`     | Immutable day record: headline, summary, full text, mood, tags, user note, `aiGenerated` flag, raw `BodySnapshot`.                                                                                                                 |
| `BodySnapshot`      | Flat struct of every collected metric for one day: steps, calories, distance, sleep, `avgHeartRate`, `restingHeartRate`, `hrv`, workouts, environmental data, calendar events. Serialisation-ready for persistence and AI prompts. |
| `BleHrReading`      | Single BLE HR measurement: `bpm` + `rrMs` list (RR intervals in ms for real-time HRV). Emitted by `BleHeartRateService`.                                                                                                           |
| `CaptureEntry`      | Point-in-time snapshot (health + env + location + calendar). Carries `isProcessed` / `processedAt` for the refresh pipeline, plus optional `CaptureAiMetadata`.                                                                    |
| `CaptureAiMetadata` | AI-derived per-capture metadata: summary, themes, energy level, mood assessment, tags, notable signals. Stored as JSON in the `captures` table (schema v7).                                                                        |
| `JournalAiResult`   | Parsed AI output: headline, summary, full body, mood, mood emoji, tags.                                                                                                                                                            |

### Provider Architecture

All services are exposed as `Provider<T>` singletons via `service_providers.dart`. Screens consume them with `ref.read(someServiceProvider)`, which guarantees a single SQLite connection, makes every service replaceable in tests, and eliminates scattered state.

---

## How the AI Journal Works

### Smart Refresh Pipeline

```
getTodayEntry()                       ← called on every Journal visit
  │
  ├─ INSTANT      — persisted entry exists, 0 unprocessed captures
  │                  → return immediately (no sensors, no AI, no network)
  │
  ├─ INCREMENTAL  — persisted entry exists, N unprocessed captures
  │                  → AI runs on new captures only → persist → mark processed
  │
  └─ COLD START   — no entry for today
                    → collect sensors → local template → AI enrich → persist
```

### Capture → Journal Flow

1. `CaptureService` (manual) or `BackgroundCaptureService` (WorkManager) creates a capture.
2. Each starts with `is_processed = 0`.
3. `getTodayEntry()` detects unprocessed captures → runs AI only when needed.
4. On success, `markCapturesProcessed()` flips the flag.
5. Next visit → zero unprocessed → instant return from cache.

### AI Details

- **Endpoint:** `POST ai.governor-hq.com`
- **System prompt:** First-person voice — "the body speaking to its person." Warm, poetic, data-grounded. Never clinical, never medical advice.
- **Context window:** 7-day rolling history fed into every prompt (`ContextWindowService`).
- **Fallback:** On timeout (45 s) or parse error, the local template entry is returned unchanged.
- **`aiGenerated` flag:** Persisted in SQLite so the ✦ badge survives restarts.
- **`regenerateWithAi(date)`:** Force a fresh AI pass for any date from the journal detail screen.

### Mood Inference (v1 — Heuristic)

```
sleep ≥ 7 h  AND  steps ≥ 5 000  AND  HR > 0   →  energised
sleep < 5 h                                       →  tired
steps ≥ 8 000                                     →  active
AQI > 100                                         →  cautious
sleep ≥ 7 h                                       →  rested
steps = 0  AND  calories = 0                      →  quiet
default                                           →  calm
```

Will be replaced by a classifier or LLM prompt once sufficient labelled data exists.

---

## Screens

| #   | Screen             | Route               | Description                                                                                                                                                                                                                    |
| --- | ------------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | **Onboarding**     | `/onboarding`       | Permission flow — location, health, calendar. Every step skippable.                                                                                                                                                            |
| 2   | **Journal**        | `/journal` (Tab 0)  | Paginated daily blog. Swipe between days. Pull-to-refresh + "Refresh day" on today's card.                                                                                                                                     |
| 3   | **Journal Detail** | —                   | Full narrative: Sleep, Movement, Heart, Environment, Agenda. AI regeneration & mood/note editor.                                                                                                                               |
| 4   | **Patterns**       | `/patterns` (Tab 1) | Energy distribution, top themes, keyword tags, notable signals, recent moments timeline.                                                                                                                                       |
| 5   | **Capture**        | `/capture` (Tab 2)  | Manual capture with toggleable data sources. **BLE HR chip** opens a device scanner; once connected, a live ECG-style waveform slides in above the sensor row. Tapping the shutter snapshots the current BPM into the capture. |
| 6   | **Environment**    | `/environment`      | Expanded environmental data view.                                                                                                                                                                                              |
| 7   | **Debug**          | `/debug`            | Raw sensor readouts — health metrics, GPS, ambient data, calendar events.                                                                                                                                                      |

---

## Development

### Day-to-day

```bash
flutter analyze          # static analysis — must pass with zero errors
flutter test             # run the test suite
dart format lib/         # format everything
flutter test --coverage  # generate coverage/lcov.info
```

Hot reload: `r` · Hot restart: `R` · Quit: `q`

### Journal Pipeline Layers

Understanding these three layers prevents accidental slowdowns:

| Layer         | File                      | Responsibility                                  |
| ------------- | ------------------------- | ----------------------------------------------- |
| Persistence   | `local_db_service.dart`   | SQLite CRUD for entries, captures, settings     |
| Orchestration | `body_blog_service.dart`  | Smart refresh, sensor collection, AI enrichment |
| AI            | `journal_ai_service.dart` | Prompt building, API call, JSON parsing         |

**Key rule:** `getTodayEntry()` is called on every Journal visit. The fast path (persisted entry + zero unprocessed captures) must return with no I/O beyond two DB queries.

### Adding a New Service

1. Create `lib/core/services/your_service.dart`.
2. Expose a Riverpod `Provider<YourService>` in `service_providers.dart`.
3. Wire into `BodyBlogService` or the relevant feature screen.

### Adding a New Feature Screen

1. Create `lib/features/your_feature/screens/your_screen.dart`.
2. Add a route in `lib/core/router/app_router.dart`.
3. For a top-level tab, add a `StatefulShellBranch` to the shell route.

### Database Migrations

Schema version lives in `local_db_service.dart` (`_schemaVersion`, currently **7**).

1. Bump `_schemaVersion`.
2. Add an `if (oldVersion < N)` block in `_onUpgrade()`.
3. Wrap `ALTER TABLE` statements in try/catch for duplicate-column safety (hot-restart resilience).

### Testing on Emulators

| Data source      | Emulator / test setup                                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Health (Android) | Install Health Connect, add test data manually                                                                                                   |
| Health (iOS)     | Physical device required — HealthKit unavailable in Simulator                                                                                    |
| Location         | Set coordinates via emulator extended controls                                                                                                   |
| Calendar         | Add events in the device calendar app                                                                                                            |
| Environment      | Requires valid GPS to query ambient-scan API                                                                                                     |
| BLE HR           | Physical BLE device required — Bluetooth is unavailable in Android Emulator & iOS Simulator. Use a Polar H10, Wahoo TICKR, or any 0x180D device. |

All data fetches have 5–15 s timeouts. The app shows zero/empty states for unavailable sensors — never fake data (see `CODING_PRINCIPLES.md`).

### Pre-commit Checklist

- [ ] `flutter pub get` — no unresolved deps
- [ ] `dart format lib/` — formatter applied
- [ ] `flutter analyze` — 0 errors, 0 warnings
- [ ] `flutter test` — all green
- [ ] New screens wired in `app_router.dart`
- [ ] README architecture tree & screen list updated
- [ ] Roadmap checkbox ticked if feature was shipped
- [ ] No fake data

---

## Principles

- **No fake data.** Sensor unavailable → zero or null, never a plausible placeholder.
- **No location tracking.** GPS read once for the environment fetch, then discarded.
- **Read-only health access.** Never writes to HealthKit or Health Connect.
- **Graceful degradation.** Every data fetch has a timeout. The app never freezes waiting for a sensor.

These are enforced by `CODING_PRINCIPLES.md`.

---

## Roadmap

### Shipped

- [x] LLM-backed narrative generation (captures-first, snapshot fallback, local template on failure)
- [x] SQLite persistence for entries, captures, and settings (schema v7)
- [x] 7-day rolling context window for AI prompts
- [x] User annotations (free-text note + mood emoji per day)
- [x] Smart refresh — instant cache, incremental AI, capture-processed tracking
- [x] Background captures via WorkManager (quiet hours, battery awareness)
- [x] Manual capture with configurable data-source toggles
- [x] "Refresh day" button for user-triggered full sensor + AI refresh
- [x] Per-capture AI metadata extraction (`CaptureMetadataService`)
- [x] Patterns screen — progressive AI-derived insights from capture history
- [x] Share journal entries (`share_plus`)
- [x] CI pipeline with APK artefact upload
- [x] Resting heart rate + HRV (SDNN) from HealthKit / Health Connect — included in `BodySnapshot` and AI prompts
- [x] BLE Heart Rate Profile (0x180D) — device scan, connect, live BPM stream with RR intervals
- [x] Live ECG-style PQRST waveform widget (`LiveHrWaveform`) in the Capture screen
- [x] BLE snapshot BPM auto-attached to captures (`bleHeartRate` param in `CaptureService`)

### Next — BLE Peripherals

- [ ] Continuous background BLE data collection while app is backgrounded
- [ ] Real-time HRV derived from BLE RR intervals (RMSSD, pNN50)
- [ ] BLE pulse oximeters (SpO₂) and smart scales

### Next — Home Automation

- [ ] Smart-home integration (Matter, HomeKit, MQTT)
- [ ] Physiological-state-driven rules (sleep → dim lights, wake → start coffee)
- [ ] User-defined trigger engine based on body + environment state

### Future

- [ ] On-device ML for mood/state classification
- [ ] Multi-user household awareness (BLE presence + individual profiles)
- [ ] Wearable companion (Wear OS / watchOS)
- [ ] Export to structured health records (FHIR-compatible)

---

## License

MIT
