# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MotoDash is a native iOS motorcycle dashboard app (iPhone only, iOS 16+) built in Swift/SwiftUI with no external dependencies. It displays GPS telemetry and Bluetooth TPMS tire pressure data in a custom dashboard UI with home/lock screen widgets.

## Build & Development

This project uses **xcodegen** to generate the Xcode project from `project.yml`. The `.xcodeproj` is not committed.

```bash
# Install xcodegen (once)
brew install xcodegen

# Regenerate .xcodeproj after any project.yml changes
xcodegen generate

# Build unsigned IPA (matches CI)
xcodebuild -scheme MotoDash \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

**Run `xcodegen generate` whenever `project.yml` changes** (adding files, changing entitlements, etc.) before building.

No linter, formatter, or test suite is configured. Testing is manual on a physical device (GPS and BLE require real hardware).

## CI/CD

GitHub Actions (`.github/workflows/build.yml`) builds an unsigned IPA on push to `main` affecting `App/**`, `Widget/**`, `Shared/**`, or `project.yml`. Xcode version is pinned to 16.4 on macOS 15. Artifacts are retained for 14 days and sideloaded via Sideloadly on Windows.

## Architecture

### Data Flow

```
GPS (CoreLocation)
  └─► RideManager (@MainActor, ObservableObject)
        ├─ Publishes: speedKMH, altitudeM, tripMeters, totalMeters, ridingSeconds, headingDegrees
        ├─ Filters: rejects accuracy > 50m and speed jumps > 100 km/h
        ├─ Smoothing: 30% previous + 70% raw GPS speed
        └─ Persists to SharedStore → triggers WidgetKit reload (throttled to 60s)

BLE Advertisements (CoreBluetooth)
  └─► TPMSManager (NSObject, ObservableObject, CBCentralManagerDelegate)
        ├─ Passes raw manufacturer data through parser plugins
        ├─ Matches packets to assigned front/rear sensors by UUID
        ├─ Fires UNNotification on pressure < 1.8 bar (10-min cooldown)
        └─ Persists sensor assignments to UserDefaults

SharedStore (App Group: group.com.tadashi.motodash)
  └─► RideWidget (WidgetKit) — reads on timeline refresh
```

Both `RideManager` and `TPMSManager` are injected as `@EnvironmentObject` from `MotoDashApp`.

### Key Files

| File | Purpose |
|------|---------|
| `App/MotoDashApp.swift` | App entry point; owns `@StateObject` for both managers |
| `App/Ride/RideManager.swift` | GPS telemetry, trip tracking, SharedStore writes |
| `App/TPMS/TPMSManager.swift` | BLE scanning, sensor pairing, pressure alerts |
| `App/TPMS/TPMSModels.swift` | `TPMSAdvertisementParser` protocol + `CommonChineseTPMSParser` |
| `App/UI/DashboardView.swift` | Main UI with portrait/landscape responsive layout |
| `App/UI/SnifferView.swift` | BLE debug sheet; shows raw hex packets, assigns sensors |
| `App/UI/SpeedGauge.swift` | Custom curved L-shaped gauge with tick marks |
| `Shared/SharedStore.swift` | App Group UserDefaults wrapper (app ↔ widget) |
| `Widget/RideWidget.swift` | WidgetKit: home screen (small/medium) + lock screen widgets |
| `project.yml` | xcodegen config — source of truth for targets, entitlements, build settings |

### TPMS Parser Plugin System

To support a new TPMS sensor brand:
1. Implement `TPMSAdvertisementParser` protocol in `App/TPMS/TPMSModels.swift`
2. Add an instance to `TPMSManager.parsers` array in `TPMSManager.swift`
3. Use `SnifferView` (tap the tire pressure panel on the dashboard) to inspect raw hex packets from the new sensor

### UI Conventions

- Always dark mode (`.preferredColorScheme(.dark)`), black background
- Accent color: lime green `Color(red: 0.65, green: 0.95, blue: 0.15)`
- Full-bleed layout using `.ignoresSafeArea()`
- Dual layout via `GeometryReader`: portrait = vertical stack, landscape = gauge left + telemetry grid right
- Long-press the Trip cell to reset trip distance

### Threading

- `RideManager` is `@MainActor`; delegate callbacks use `Task { @MainActor in ... }`
- `TPMSManager` uses the same pattern for `CBCentralManagerDelegate` callbacks
- No GCD (`DispatchQueue`) — Swift Concurrency throughout

### Persistence

- Trip/total/time: `SharedStore` (App Group UserDefaults, shared with widget)
- Sensor assignments: `TPMSManager` (standard UserDefaults)
- Widget refresh is throttled: app only calls `WidgetCenter.shared.reloadAllTimelines()` when >60s have elapsed since last reload
