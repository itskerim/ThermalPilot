# Architecture

Thermal Pilot is a small, deliberately layered SwiftUI menu-bar app. The product name is **Thermal Pilot**; the Swift package and executable are historically named **FanUsage**.

---

## Package layout

Defined in [`Package.swift`](../Package.swift) (`swift-tools-version: 6.2`, `macOS(.v14)`):

```
FanUsage (package)
├── FanUsageCore     ── library   ── all metric reading & models (links IOKit)
├── FanUsageApp      ── executable ── SwiftUI UI + diagnostics (depends on Core)
└── FanUsageCoreTests ── test target ── unit tests for the Core logic
```

The split is intentional: **`FanUsageCore` has zero UI** and zero app dependencies, so the data layer is unit-testable in isolation and easy to audit for the "no network" claim.

### `Sources/FanUsageCore` — the data layer

| File | Responsibility |
| --- | --- |
| [`Models.swift`](../Sources/FanUsageCore/Models.swift) | All value types: `HardwareSnapshot`, `FanReading`, `CPUReading`, `MemoryReading`, `ThermalReading`, `BottleneckReading`, the enums (`MemoryStatus`, `MemoryCategory`, `TemperatureUnit`, `MenuBarDisplayMode`, `BottleneckSeverity`), the `DisplayValueFormatter` (rounding/units → display strings), and `MetricValidation` (impossible-value detection). Every type is `Sendable`. |
| [`HardwareMetricsProviding.swift`](../Sources/FanUsageCore/HardwareMetricsProviding.swift) | The `HardwareMetricsProviding` protocol, the `CompositeHardwareProvider` that fans out to the three providers and assembles a `HardwareSnapshot`, the `UnavailableSensorProvider` fallback, and `BottleneckAnalyzer` (the slowdown verdict). |
| [`SystemCPUProvider.swift`](../Sources/FanUsageCore/SystemCPUProvider.swift) | CPU usage via `host_statistics(HOST_CPU_LOAD_INFO)`, diffing two tick samples; chip name via `sysctl`. Holds the previous sample behind an `NSLock`. |
| [`SystemMemoryProvider.swift`](../Sources/FanUsageCore/SystemMemoryProvider.swift) | RAM via `host_statistics64(HOST_VM_INFO64)` + `host_page_size`; top processes via `/bin/ps`. `MemoryUsageCalculator` turns raw VM page counts into the used/available/breakdown/pressure/status numbers (pure function, fully tested). |
| [`SMCSensorProvider.swift`](../Sources/FanUsageCore/SMCSensorProvider.swift) | Fans and temperatures from the SMC over IOKit. Includes the low-level `AppleSMCReader` (IOKit struct calls, four-char-code keys, `flt`/`fpe2`/`sp78`/`ui8/16/32` decoding), the `SMCReading` protocol, a `FixtureSMCReader` for tests, and the thermal stability filter. |

### `Sources/FanUsageApp` — the UI layer

| File | Responsibility |
| --- | --- |
| [`FanUsageApp.swift`](../Sources/FanUsageApp/FanUsageApp.swift) | `@main`. Declares the `MenuBarExtra` scene (`.window` style), wires `@AppStorage` preferences, and renders the menu-bar label (CPU% / Fan RPM / Temperature / icon-only). Runs diagnostics on launch if CLI flags are present. |
| [`MetricsModel.swift`](../Sources/FanUsageApp/MetricsModel.swift) | `@MainActor ObservableObject`. Owns the refresh loop: publishes the current `HardwareSnapshot`, the countdown to next refresh, last-refresh duration, and a staleness flag. Re-entrancy guarded so overlapping refreshes are dropped. |
| [`ContentView.swift`](../Sources/FanUsageApp/ContentView.swift) | The entire panel UI (~1,950 lines): sidebar with scroll-spy, the per-metric sections, the memory breakdown bar + process grouping + icon resolution, the slowdown card, settings controls, tooltips, and the custom "premium" controls (segmented control, toggle, progress bar). |
| [`Diagnostics.swift`](../Sources/FanUsageApp/Diagnostics.swift) | The `--qa-sample` and `--diagnose-sensors` CLI paths and their JSON record types. See [QA.md](QA.md). |

---

## Data flow

```
                 every refreshInterval seconds
                 (MetricsModel.refreshLoop, MainActor)
                              │
                              ▼
        CompositeHardwareProvider.snapshot()
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
 SystemCPUProvider   SystemMemoryProvider    SMCSensorProvider
 host_statistics     host_statistics64        IOKit → AppleSMC
 (CPU ticks)         + /bin/ps (top procs)    (fans + thermals)
        └─────────────────────┼─────────────────────┘
                              ▼
                 BottleneckAnalyzer.analyze()
                              │
                              ▼
                     HardwareSnapshot ──► MetricValidation.warnings()
                              │
                              ▼
              @Published snapshot on MetricsModel
                              │
                              ▼
                        ContentView re-renders
```

`CompositeHardwareProvider.snapshotSync()` is the single synchronous assembly point — it stamps `readStartedAt`/`readEndedAt` (used for the "refresh took N ms" and staleness signals), appends availability warnings when fans/thermals are empty, runs the bottleneck analysis, and folds in validation warnings. The async `snapshot()` just wraps it so the same code path serves both the UI and the QA sampler.

### Refresh loop details

- Interval is user-configurable (1s / 3s / 5s / 10s), clamped to ≥1s.
- The loop counts down second-by-second so the UI can show "Next update in Ns".
- A refresh that's already running is skipped (`isRefreshing` guard) to avoid pile-ups if a read is slow.
- A snapshot is marked **stale** if the read took longer than `2 × interval`.

---

## Preferences

Stored in `UserDefaults` via `@AppStorage` — the **only** persisted state:

| Key | Default | Controls |
| --- | --- | --- |
| `refreshInterval` | `3.0` | Sampling cadence |
| `temperatureUnit` | `celsius` | °C / °F |
| `menuBarDisplayMode` | `cpu` | What shows beside the menu-bar icon |
| `launchAtLogin` | `false` | Registers via `ServiceManagement` (`SMAppService`) |

No files, no database, no network. That's the entire footprint.

---

## SMC access, explained

The SMC (System Management Controller) is the chip that runs fans and exposes temperature/voltage sensors. There's no public Apple API for it, so `AppleSMCReader`:

1. Opens the `AppleSMC` IOKit service (`IOServiceGetMatchingService` → `IOServiceOpen`).
2. For each key, issues a `readKeyInfo` call (to learn the value's type and size), then a `readBytes` call.
3. Decodes the bytes per the SMC type tag — `flt ` (IEEE float), `fpe2` (unsigned fixed-point /4), `sp78` (signed fixed-point /256), and `ui8/ui16/ui32` integers.
4. Keys are four-character codes packed into a `UInt32` (`FNum`, `F0Ac`, `Tp09`, …).

If the service can't be opened (sandboxing, permissions, or a Mac that doesn't expose it), every read returns `nil` and the UI shows "Unavailable" — it never crashes or fabricates a value. Because SMC access requires IOKit, `FanUsageCore` links the `IOKit` framework (see `Package.swift`).

---

## Packaging

[`scripts/package-app.sh`](../scripts/package-app.sh) builds the release binary and assembles a distributable `.app`, `.dmg`, and `.zip`:

1. `swift build -c release` (with a local module cache).
2. Lays out `build/Thermal Pilot.app/Contents/{MacOS,Resources}` and copies the binary.
3. Generates the icon: [`scripts/generate-app-icon.swift`](../scripts/generate-app-icon.swift) renders an `.iconset` from `assets/AppIcon.png`, then `iconutil` → `AppIcon.icns`.
4. Writes `Info.plist` — bundle id `local.thermalpilot.app`, `LSUIElement` true (menu-bar only, no Dock icon), `LSMinimumSystemVersion` 14.0.
5. Ad-hoc code-signs (`codesign --sign -`) — **not** notarized, hence the Gatekeeper prompt on first launch.
6. Produces the `.zip` (`ditto`) and a custom `.dmg`: stages the app + an `/Applications` symlink, paints a Finder background ([`scripts/generate-dmg-background.swift`](../scripts/generate-dmg-background.swift)) and positions the icons via AppleScript, then converts to a compressed read-only `UDZO` image.

Run it with `scripts/package-app.sh release` (or `debug`). Outputs land in `build/`.

---

## Testing

[`Tests/FanUsageCoreTests`](../Tests/FanUsageCoreTests) covers the pure logic in Core:

- **CPU**: usage math across samples, zero-delta, idle/full load, counter rollback → 0.
- **Memory**: normal/elevated/high classification, treating inactive pages as available.
- **SMC**: fan fixture parsing, unavailable-sensor handling, rejecting implausible thermal drops/spikes and recovering, per-key stable-value retention, numeric decoding of every SMC type, rejecting bad sizes/unknown types.
- **Formatting & validation**: documented rounding and "Unavailable" text, the loading placeholder, impossible-value flagging.
- **Bottleneck**: memory-pressure and thermal-limit precedence.

Run with `swift test`. Because the UI sits on top of a tested, dependency-injected Core (providers are swappable via protocols and `FixtureSMCReader`), the risky parsing logic is verified without needing the real hardware.
