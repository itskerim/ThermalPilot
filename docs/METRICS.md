# Metrics Reference

This is the definitive guide to every number Thermal Pilot shows: **what it means, where it comes from, and how to act on it.** Nothing here is estimated or phoned home — each value is read locally from a public macOS API or an SMC (System Management Controller) sensor key.

Source of truth in code: [`Sources/FanUsageCore`](../Sources/FanUsageCore).

---

## Panels overview

The panel has a sidebar with five content tabs plus settings:

| Tab | Icon | Contents |
| --- | --- | --- |
| **Overview** | gauge | Fans summary, CPU, Memory, and the Slowdown verdict in one scroll |
| **Fans** | fan | Per-fan RPM, range, and % of range |
| **CPU** | chip | Total usage and core count |
| **Memory** | pie | Use %, pressure, RAM breakdown, top memory users |
| **Thermals** | thermometer | Per-sensor temperatures |
| **Settings** | gear | Refresh rate, menu-bar metric, °C/°F, launch at login |

The sidebar scroll-spies: scrolling the content highlights the matching tab; clicking a tab scrolls to that section.

---

## 🌀 Fans

**What you see:** one row per fan — current **RPM**, the fan's **min–max range**, and **% of range** (how hard it's spinning relative to its own floor and ceiling). The header pill shows how many fans are active.

**Source:** the SMC, read over IOKit (`AppleSMC` service).

| Reading | SMC key | Notes |
| --- | --- | --- |
| Fan count | `FNum` | If `0` or missing, there are no controllable fans (fanless Mac, or SMC doesn't expose them) |
| Current RPM | `F0Ac`, `F1Ac`, … | The live speed |
| Minimum RPM | `F0Mn`, `F1Mn`, … | The fan's idle floor |
| Maximum RPM | `F0Mx`, `F1Mx`, … | The fan's redline |
| Fan label | `F0ID`, `F1ID`, … | A name if the firmware provides one; otherwise "Fan 1", "Fan 2" |

**% of range** = `(current − min) / (max − min)`, clamped to 0–100%. A fan at "0% of range" is idling; "80% of range" means it's nearly maxed and your Mac is working to shed heat.

**If it says "Unavailable":** many Apple Silicon Macs (and all fanless ones like the MacBook Air) either have no fans or don't expose fan keys to third-party apps. Thermal Pilot reports this honestly rather than inventing a number. You'll see an availability warning: *"Fan sensors unavailable on this Mac or blocked by SMC permissions."*

---

## ⚙️ CPU

**What you see:** **Total usage %** across all cores, the **core count**, and the **chip model name** (e.g. "Apple M4 Pro").

**Source:** `host_statistics(HOST_CPU_LOAD_INFO)` for tick counters; `sysctl machdep.cpu.brand_string` for the model name; `ProcessInfo.processorCount` for cores.

**How usage is computed:** the kernel reports cumulative CPU ticks split into *user / system / idle / nice*. Thermal Pilot takes two samples and computes:

```
usage% = (activeDelta / totalDelta) × 100
       = (totalDelta − idleDelta) / totalDelta × 100
```

So it's the share of time **not** spent idle between two refreshes. The first reading after launch is `0%` (no previous sample to diff against) — it populates on the next refresh.

> **Why it differs slightly from Activity Monitor:** Activity Monitor can show >100% (it sums per-core, so 14 cores = up to 1400%). Thermal Pilot normalizes to a single **0–100% whole-machine** figure, and its sampling window is your chosen refresh interval rather than Activity Monitor's. Both are correct; they answer slightly different questions. The label says *"Public host CPU stats"* to make the source explicit.

---

## 🧠 Memory

The richest panel. **Source:** `host_statistics64(HOST_VM_INFO64)` for page counts, `host_page_size` for page size, `ProcessInfo.physicalMemory` for total RAM, and `/bin/ps -axo pid,ppid,rss,comm` for per-process resident memory.

### Memory use

Physical RAM in use as a % of total. "Used" = **Active + Wired + Compressed** pages × page size. This is the headline "how full is my Mac" number, shown alongside the absolute used/available figures.

### Pressure

A 0–100% reading of how hard macOS is working to keep memory available. Thermal Pilot derives this from used-vs-total and the size of the compressor pool, then buckets it into a status:

| Status | Trigger | Meaning |
| --- | --- | --- |
| **Normal** | pressure < 74% and compressed < 10% of RAM | Plenty of headroom |
| **Elevated** | pressure ≥ 74%, or compressed > 10% of RAM | Getting tight; macOS is compressing |
| **High** | pressure ≥ 88%, or compressed > 20% of RAM | Under real pressure; expect swapping and slowdowns |

> **Pressure, not "used", is what predicts lag.** macOS deliberately fills unused RAM with cache, so a high "used" number alone is fine. It's *pressure* — heavy compression and swapping — that makes your Mac feel slow. Watch this number when things get sluggish.

### RAM breakdown

A stacked bar plus a legend, splitting total RAM into five categories. Hover any item for an inline explanation.

| Category | What it is | Page source |
| --- | --- | --- |
| **Active** | Memory in active use by running apps | `active_count` |
| **Wired** | Memory the kernel must keep resident — can't be compressed or paged out | `wire_count` |
| **Compressed** | Memory macOS squeezed to avoid writing to disk | `compressor_page_count` |
| **Cached** | Recently used file/app data macOS can reclaim instantly when apps need RAM | `inactive_count` + `speculative_count` |
| **Free** | Unused, immediately available | `free_count` |

**Available** (shown next to the breakdown) = Free + Cached (inactive + speculative). That's how much an app could grab *right now* without forcing a swap.

> A low **Free** number is **not** a problem. macOS uses idle RAM as disk cache to make everything faster; it hands that memory back the instant an app asks. The number that matters is **Available** and **Pressure**, not Free.

### Top memory users — "what's eating my RAM"

A ranked list of processes by **resident memory (RSS)**, read from `ps`. The key feature: **processes are grouped by their parent application.**

Modern apps spawn many helper processes. Chrome alone can run 20+ `Google Chrome Helper` processes; Electron apps, ChatGPT Atlas, Codex, Figma, and browsers all do this. Thermal Pilot:

1. Walks each process up to its owning `.app` bundle (the **outermost** bundle, so `Chrome.app/.../Google Chrome Helper.app` rolls up to **Google Chrome**).
2. Falls back to name-pattern grouping for known multi-process apps (Chrome, ChatGPT Atlas, Codex, Microsoft Edge, Brave, Arc, Safari WebKit content) and generic `… Helper` / `(Renderer)` / `(GPU)` / `(Service)` / `(Plugin)` suffixes.
3. Shows the parent as an **expandable row** with a child count badge and the **summed** memory; expand it to see individual children.

A standalone process that isn't part of an app bundle — like a bare `node`, `python`, `ollama`, or a local LLM runner — shows up under its own name with its real RSS, so **you can immediately tell which heavy local model or background job is the culprit.** Each row carries the app's real icon (resolved from the bundle) for fast scanning.

> **This is the panel to open when your Mac is choking.** It answers "is it the browser, the local model, or that build I forgot about?" in one glance, then lets you go quit the right thing.

---

## 🌡️ Temperature (Thermals)

**What you see:** a row per available sensor with its temperature, in your chosen unit (°C or °F).

**Source:** the SMC. Thermal Pilot probes a curated set of keys and shows the ones that return plausible values:

| Label | SMC key |
| --- | --- |
| CPU Proximity | `TC0P` |
| CPU Core 1 | `TC0E` |
| CPU Core 2 | `TC0F` |
| SoC | `Tp09` |
| Die | `Te05` |

**Stability filtering:** raw SMC thermal reads can glitch — implausible spikes, sudden 40°C drops, or out-of-range garbage. Thermal Pilot rejects values outside 15–115°C, suppresses physically impossible jumps (>35°C swing between reads), cross-checks the SoC sensor against the die sensor, and falls back to the last stable per-key value when a read looks wrong. So the displayed temperature is smoothed for plausibility, not the raw byte.

**If it says "Unavailable":** some Macs don't expose CPU/SoC thermal keys to userspace. You'll get the warning *"CPU temperature unavailable without compatible SMC thermal keys."* — again, honest rather than faked.

**Unit toggle:** Settings → Temperature → **C / F**. Conversion is the standard `°F = °C × 9/5 + 32`.

---

## 🚦 Slowdown (the verdict)

Rather than make you interpret five panels, Thermal Pilot collapses everything into **one plain-English bottleneck verdict** with a severity, a progress bar, and a detail line. Logic lives in `BottleneckAnalyzer`.

Evaluated in priority order (first match wins):

| Verdict | Severity / pill | Condition |
| --- | --- | --- |
| **Memory pressure** | Critical / "Limit" | memory status is **High** |
| **Thermal limit** | Critical / "Limit" | hottest sensor ≥ 88°C |
| **CPU-bound** | Warning / "Busy" | CPU usage ≥ 82% |
| **Memory getting tight** | Notice / "Watch" | memory status is **Elevated** |
| **Cooling active** | Notice / "Watch" | fan load ≥ 72% **or** hottest sensor ≥ 78°C |
| **No obvious bottleneck** | Normal / "Clear" | none of the above — CPU, memory, and thermals look healthy |

The detail line explains the call (e.g. for *Thermal limit*: *"Hottest sensor is 89 deg C; macOS may reduce performance"*; for *Memory pressure*: the used / available / compressed figures). The progress bar reflects the dominant metric driving the verdict.

> Use this as your "should I worry?" glance. **Clear** = carry on. **Watch** = something's warming up but fine. **Busy / Limit** = open the matching panel to see what and act.

---

## Availability & validation warnings

Two kinds of warnings can surface under the metrics:

- **Availability warnings** — a sensor isn't exposed on this Mac (no fans, no thermal keys, SMC blocked).
- **Validation warnings** — a reading came back physically impossible (negative RPM, used > total RAM, temperature out of 0–115°C, inverted fan range). These are flagged rather than displayed as fact, via `MetricValidation`.

Both are visible in the UI and included in `--qa-sample` output so you can audit accuracy. See [QA.md](QA.md).
