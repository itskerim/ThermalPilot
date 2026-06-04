# FAQ & Troubleshooting

### Does Thermal Pilot send any data anywhere?
No. It makes no network connections, has no analytics, and no accounts. It reads everything locally from the kernel and the SMC. The whole data layer is in [`Sources/FanUsageCore`](../Sources/FanUsageCore) if you want to verify.

### Why is there no Dock icon or app window?
Thermal Pilot is a menu-bar utility (`LSUIElement`). It lives only in the menu bar, beside Control Center. Click the icon to open the panel.

### macOS says the app "cannot be opened" / "is from an unidentified developer."
It's ad-hoc signed but not notarized. Right-click the app → **Open**, or allow it in **System Settings → Privacy & Security → "Open Anyway"**. Full steps in [INSTALL.md](INSTALL.md#first-launch-gatekeeper).

### My fans show "Unavailable." Is something broken?
No. Many Macs — especially fanless ones like the MacBook Air, and some Apple Silicon models — either have no fans or don't expose fan SMC keys to third-party apps. Thermal Pilot reports this honestly instead of faking a number. Run `swift run FanUsage --diagnose-sensors` to see exactly what the SMC returns.

### Temperature shows "Unavailable" too.
Same reason — some Macs don't expose CPU/SoC thermal keys (`Tp09`, `Te05`, `TC0P`, …) to userspace. The diagnose-sensors dump will show whether those keys return `nil` on your machine.

### CPU % doesn't match Activity Monitor.
Both are right; they answer different questions. Activity Monitor sums per-core (so 14 cores can read up to 1400%). Thermal Pilot normalizes to a single whole-machine **0–100%** and samples over your chosen refresh interval. See [METRICS.md](METRICS.md#-cpu).

### "Free" memory is tiny / "used" is always high. Is my Mac out of RAM?
Almost certainly not. macOS deliberately fills idle RAM with reclaimable cache, so low **Free** is normal and *healthy*. The numbers that predict slowdowns are **Pressure** and **Available**, not Free. Watch the Pressure bar and the Slowdown verdict instead. See [METRICS.md](METRICS.md#pressure).

### What's the difference between "Memory use" and "Pressure"?
"Memory use" is how full RAM is right now (Active + Wired + Compressed). "Pressure" is how hard macOS is working to keep memory available — heavy compression and swapping. Pressure is the one that correlates with your Mac feeling slow.

### Why is Chrome shown as one row when it has 20 processes?
Thermal Pilot groups helper processes under their owning app bundle and sums their memory, so you see one **Google Chrome** row (with a child-count badge) instead of 20 `Google Chrome Helper` lines. Expand the row to see individual children. Standalone processes (a bare `node`, `python`, or local-model runner) appear under their own name so you can still spot a memory hog. See [METRICS.md](METRICS.md#top-memory-users--whats-eating-my-ram).

### How do I find what's eating my RAM right now?
Open the panel → **Memory** tab → **Top memory users**. It's sorted by resident memory, grouped by app, with icons. The top row is your biggest consumer; quit it from there if needed.

### How do I change what shows in the menu bar?
**Settings → Menu bar**, then pick CPU %, Fan RPM, Temperature, or Icon only.

### How do I switch to Fahrenheit?
**Settings → Temperature → F**.

### How often does it refresh, and can I change it?
Default 3 seconds. Settings offers **1s / 3s / 5s / 10s**. Faster refresh is slightly more CPU; slower is gentler on battery.

### Does it run at login?
Only if you enable **Settings → Launch at login**. It registers via macOS `ServiceManagement`; you can revoke it under System Settings → General → Login Items.

### Is the temperature reading smoothed?
Yes — raw SMC thermal reads can glitch. Thermal Pilot rejects out-of-range and physically-impossible jumps and falls back to the last stable value per sensor. See [METRICS.md](METRICS.md#-temperature-thermals).

### How do I uninstall it cleanly?
Quit it, drag it to the Trash, and optionally `defaults delete local.thermalpilot.app`. It installs no daemons or kernel extensions. Full steps in [INSTALL.md](INSTALL.md#uninstall).

### How can I verify the numbers are accurate?
Use the built-in samplers (`--qa-sample`, `--diagnose-sensors`) and cross-check against `top`, `vm_stat`, and `memory_pressure`. See [QA.md](QA.md).

### Why is the package called "FanUsage" but the app "Thermal Pilot"?
"FanUsage" is the original internal package/executable name; "Thermal Pilot" is the product name shown to users. They refer to the same thing.
