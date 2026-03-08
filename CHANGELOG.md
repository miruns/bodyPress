# Changelog

All notable changes to BodyPress Flutter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.12] - 2026-03-08

### Added

- **Patterns Transparency**: Every section on the Patterns page now has an ⓘ info button that expands an explanation panel showing how the data is sourced, computed, and what it means — full algorithmic transparency
- **Theme–Energy Links**: New correlation card showing which recurring themes predict high or low energy (≥ 60 % threshold, ≥ 3 occurrences)
- **Co-Occurring Themes**: Theme-pair analysis revealing behavioural clusters that appear together in the same capture (≥ 2 co-occurrences)
- **Your Rhythms**: Circadian-rhythm strip showing capture distribution across time-of-day slots (early morning → late night)
- **AI Pattern Insights**: Aggregated AI-discovered correlations surfaced as semantic chips with contextual icons
- **Theme Trends**: Trend arrows (↑ emerging, ↓ fading) on Top Themes chips comparing newer vs older capture halves
- **Energy Dots**: Dominant energy-level indicator on each theme chip
- Staggered entrance animations (fade + slide) on all Patterns sections via `SectionCard` widget
- `PatternAnalysis` model with full correlation extraction: theme-energy map, theme trends, time-of-day distribution, co-occurrence pairs, pattern hints, location & body-signal distributions

### Changed

- Refactored Patterns page to use `PatternAnalysis` model replacing inline `_PatternSummary`
- All Patterns sections wrapped in `SectionCard` for consistent styling and info panels
- `_FrequencyChips` enhanced with optional trend arrows and energy-dot indicators

### Fixed

- Overflow in `PatternHintsCard` — long hint labels now constrained with `Flexible` + ellipsis

## [1.0.11] - 2026-03-08

### Added

- **Refresh Journey Overlay**: Immersive refresh experience with live pipeline stages (Reading body → Saving snapshot → AI composing → Ready), breathing animations, tone badge, rotating inspirational phrases, and elapsed timer

### Changed

- Removed BodyHarmonyRing and VitalityWave widgets from Blog page (cleanup)
- Fixed center alignment for More tab in navigation content

## [1.0.10] - 2026-03-07

### Added

- **Bring-Your-Own-AI**: AI provider configuration screen with custom endpoint support and chat completions URI builder
- **Foreground Service**: Persistent foreground service for background monitoring and push notifications
- **Tone Selection**: Tone picker for body journal entries with updated AI narrative generation
- Exact alarm permission handling for notification scheduling
- Sensor guidance tips and attention indicators in the More sheet
- GeoIP fallback and caching mechanism for location services
- Sensor health indicator and permission management UI components
- Animated Shimmer AI icon for entry generation and refresh actions
- Auto-refresh today's entry with fresh sensor data on app start; load past entries from DB
- Enhanced widget tests with stubs for `LocalDbService` and `BodyBlogService`

### Changed

- Refactored primary action button in BodyBlogScreen for improved UI and interaction
- Updated chat icon and button labels for entry generation functionality
- Enhanced tone selector bottom sheet with improved elevation and padding
- Removed build APK job from CI workflow

### Fixed

- Non-blocking notification updates in foreground task handler
- Tone handling in blog entry refresh logic and tone selector

## [1.0.9] - 2026-03-07

### Added

- Health permissions for resting heart rate
- Lifecycle observer to re-check health permissions after returning from Health Connect
- Health permission probing method for improved reliability

### Changed

- Updated `MainActivity` to use `FlutterFragmentActivity`
- Simplified onboarding logic to check permissions and sync DB flag

## [1.0.8] - 2026-03-06

### Added

- Hardcoded daily reminders: morning and evening notification schedules

### Changed

- Removed unused notification time picker and related variable

## [1.0.7] - 2026-03-03

### Added

- **Insight Reflection Card** widget for journal insights
- **Vitality Wave** animated health visualization widget
- **Weekly Self Portrait** summary widget
- Interval filtering for captures with UI integration

## [1.0.6] - 2026-03-02

### Added

- **Sensors screen** with dedicated routing integration

### Fixed

- Renamed More destination label from "Settings" to "Environment"
- Updated ShareFab background and text colors for improved visibility

## [1.0.5] - 2026-03-02

### Added

- **BLE Heart Rate Monitoring**: Bluetooth Low Energy heart rate device integration with capture service
- Heart rate chip display on capture screen
- Heart rate session recording with HRV metrics calculation
- SnackBar color and theme integration in CaptureScreen

### Fixed

- Various bug fixes for BLE connectivity and data handling

## [1.0.4] - 2026-03-02

### Added

- **Social Sharing**: SocialCard widget with `share_plus` integration for sharing journal entries
- Background processing for unprocessed AI metadata captures
- Version history tracking for body blog entries
- Full-screen camera experience for the capture screen

### Changed

- Streamlined layout and improved readability in Blog page widget
- Updated BodyBlogScreen layout for improved UI responsiveness
- Simplified AppHeader by removing extra actions and updating theme toggle

### Fixed

- Context reference issue in dialog close action

## [1.0.3] - 2026-03-02

### Added

- Raw data badge and pending AI panel on blog entry screen
- Sensor status row with data-source indicators on blog page
- Stylish date navigation UI with separators and improved layout
- `AppHeader` widget for consistent top-bar across main screens
- Retry logic with exponential backoff for AI chat completion requests
- First-time visit check and onboarding skip logic based on critical permissions
- Immediate local draft saving with AI enrichment handling in `BodyBlogService`

### Changed

- Updated health permission messaging for clearer guidance on Health Connect access
- Improved summary formatting for sleep hours condition

## [1.0.2] - 2026-03-01

### Added

- Initialization process with timeout handling and notification scheduling
- **Zen Loader**: Optimized timing with periodic updates, engaging phrases, and improved state management

### Changed

- Removed `HomeScreen` widget and associated services (code cleanup)
- Replaced `print` statements with `debugPrint` for logging consistency

## [1.0.1] - 2026-03-01

### Added

- Enhanced AI metadata generation with multi-day correlation fields and improved prompt structure
- Capture processing pipeline with AI metadata service
- Capture-to-journal synchronization with debug display for capture count
- Release signing configuration with keystore properties

### Changed

- Simplified health permission handling in onboarding flow

### Fixed

- Default background capture configuration and daily reminder scheduling

## [1.0.0] - 2026-02-26

### Added

- **Onboarding & Permissions**
  - Onboarding screen with permission requests and skip option
  - Health, Location, and Calendar permission management with `HealthPermissionCard` widget
  - Permission state persistence with user preferences

- **Body Blog / Journal**
  - Body Blog feature with entry model and service
  - Date-based navigation with lazy loading for older entries
  - User mood feature for journal entries
  - Personalized daily blog entry opening with sleep data
  - Database migration handling for schema updates

- **AI Integration**
  - AI service integration with health check and chat capabilities
  - AI journal generation with new services and database schema
  - AI metadata processing for captures
  - AI enrichment for body blog entries with unprocessed capture handling
  - AI mode routing: local inference engine + remote mode
  - iOS-specific remote-only AI enforcement
  - Build-time AI API key injection via `--dart-define`
  - Error handling and structured logging for AI services

- **Capture System**
  - Data collection system for user state (health, location, environment)
  - Background capture with WorkManager and local notifications
  - Capture service with environmental data retrieval
  - Distance calculation utilities

- **Notifications**
  - Daily body blog notification scheduling and management
  - `POST_NOTIFICATIONS` permission support
  - Local notification integration

- **Database & Storage**
  - SQLite persistence for Body Blog entries via `LocalDbService`
  - Settings table with theme mode persistence
  - Context window service and database inspector
  - dotenv integration for environment configuration

- **Navigation & UI**
  - Multi-screen navigation: Journal, Patterns, Capture
  - AppShell with chapter indicators
  - Debug screen with environment route
  - Modern Material 3 design with overhauled `AppTheme`
  - New color palette and Inter typography via Google Fonts
  - Dark / light theme toggle with system detection

- **CI/CD & Testing**
  - GitHub Actions workflow for testing and building APK
  - Unit tests for core services and theme
  - Java 17 build environment

- **Architecture**
  - Feature-first folder structure
  - Riverpod providers for state management and dependency injection
  - GoRouter for declarative navigation
  - Clean service layer with separation of concerns

- **Platform Support**
  - Android 5.0+ (API 21+) with full permission manifest
  - iOS 14.0+ with complete Info.plist usage descriptions
  - Health Connect pre-configured (Android 13+)
  - Internet permission in AndroidManifest
