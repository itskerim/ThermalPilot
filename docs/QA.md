# QA & Accuracy

Thermal Pilot is built so you can **verify every number it shows** against the raw sensor data and against Apple's own tools. The same `CompositeHardwareProvider` that drives the UI also drives the diagnostics below, so what you audit is exactly what you see.

---

## `--qa-sample` — the JSONL sampler

Streams structured samples to stdout, one JSON object per line:

```bash
swift run FanUsage --qa-sample --count 300 --interval 1
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--count N` | `1` | Number of samples to emit |
| `--interval S` | `1` | Seconds between samples (min 0.1) |
| `--temperature-unit celsius\|fahrenheit` | `celsius` | Unit used for the `displayed` temperature strings |

Each line contains:

- **`raw`** — unrounded readings: fan RPM/min/max/normalizedLoad, CPU model/cores/usage, full memory record (every byte category, top processes with pid/ppid/path/RSS), thermals with source key.
- **`displayed`** — the **exact strings the UI would render** after rounding and unit formatting (e.g. `"82%"`, `"54 deg C"`, `"2322 RPM"`). This lets you confirm rounding matches the panel.
- **Timing** — `providerReadStartedAt` / `providerReadEndedAt` / `providerDurationMilliseconds`, plus `sampleDurationMilliseconds` and a `stale` flag (`true` when a read exceeded `2 × interval`).
- **`warnings`** — availability warnings (sensors not exposed).
- **`validationWarnings`** — physically-impossible values caught by `MetricValidation`.
- **`bottleneckTitle` / `bottleneckDetail` / `bottleneckSeverity`** — the slowdown verdict for that sample.

Because raw and displayed values sit on the same line, you can diff "what was measured" against "what was shown" for any sample.

### Useful one-liners

```bash
# Watch CPU usage (raw vs displayed) live
swift run FanUsage --qa-sample --count 60 --interval 1 \
  | jq -r '"\(.raw.cpu.usagePercent) -> \(.displayed.cpuUsage)"'

# Surface any validation warnings over a 5-minute capture
swift run FanUsage --qa-sample --count 300 --interval 1 \
  | jq -r 'select(.validationWarnings | length > 0) | .validationWarnings[]'

# Check thermal stability in Fahrenheit
swift run FanUsage --qa-sample --count 120 --interval 1 --temperature-unit fahrenheit \
  | jq -r '.displayed.thermals[]?.value'
```

---

## `--diagnose-sensors` — raw SMC dump

Prints the decoded fans/thermals snapshot plus a per-key dump of every SMC key Thermal Pilot reads, including the raw bytes and SMC type tag:

```bash
swift run FanUsage --diagnose-sensors
```

Use this to see *why* a fan or temperature shows "Unavailable" — you'll see whether the key returns `nil` (not exposed) or returns bytes that fail decoding. Keys probed: `FNum`, `F0Ac/Mn/Mx/ID`, `F1Ac/Mn/Mx/ID`, `TC0P`, `TC0E`, `TC0F`, `Tp09`, `Te05`.

---

## Cross-checking against Apple's tools

| Thermal Pilot value | Apple reference | Note |
| --- | --- | --- |
| CPU usage % | `top -l 2 -n 0` | Thermal Pilot normalizes to whole-machine 0–100%; `top` can exceed 100% (per-core sum). Compare trends, not exact digits. |
| Memory pages / breakdown | `vm_stat` | Same `HOST_VM_INFO64` page counts × page size. |
| Memory pressure | `memory_pressure` | Apple's pressure tool; Thermal Pilot's status buckets (Normal/Elevated/High) should track it. |
| Top memory users | Activity Monitor → Memory | Thermal Pilot groups helper processes under their parent app; Activity Monitor lists them flat. Sum the helpers to compare. |

> **Why values won't match to the decimal:** sampling windows differ, and tools draw category lines differently (e.g. what counts as "used" vs "cached"). Thermal Pilot's choices are documented in [METRICS.md](METRICS.md) and verified by the unit tests in [`Tests/FanUsageCoreTests`](../Tests/FanUsageCoreTests). The goal is *honest and consistent*, not *bit-identical to Activity Monitor*.

---

## Automated tests

The accuracy-critical logic is pure and unit-tested — run `swift test`. Coverage includes CPU usage math (including counter rollback), memory classification, SMC decoding of every numeric type, thermal spike/drop rejection and recovery, display-string rounding, and bottleneck precedence. See [ARCHITECTURE.md](ARCHITECTURE.md#testing).
