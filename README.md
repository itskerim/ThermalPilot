# Thermal Pilot

Know why your Mac feels slow.

<img width="1672" height="941" alt="Thermal Pilot screenshot" src="https://github.com/user-attachments/assets/f75ef0ff-8520-4dae-893d-6ad574b1a984" />

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Latest release](https://img.shields.io/github/v/release/itskerim/ThermalPilot)](https://github.com/itskerim/ThermalPilot/releases/latest)

Thermal Pilot is a lightweight menu bar app that shows what's happening inside your Mac in plain English. See CPU load, memory pressure, temperatures, fan activity, and the apps causing problems without opening Activity Monitor or digging through Terminal.

Built for Apple Silicon and Intel Macs.

## Download

Download the [latest release](https://github.com/itskerim/ThermalPilot/releases/latest) for macOS 14+.

Open the DMG, drag Thermal Pilot into Applications, and launch it from your menu bar.

## Why Thermal Pilot?

Most system monitors overwhelm you with numbers.

Thermal Pilot focuses on the information that actually matters:

- Is your Mac healthy?
- What's causing slowdowns?
- Which app is using all your memory?
- Are temperatures becoming a problem?
- Should you close something or leave it alone?

Instead of making you interpret dozens of metrics, Thermal Pilot gives you a clear overview and a simple verdict.

## Features

### Everything in one place

CPU usage, memory pressure, temperatures, fan activity, and system health live in a single panel beside Control Center.

### Find what's eating your RAM

See the largest memory consumers instantly. Chrome tabs are grouped together. Helper processes stay organized under their parent application. Rogue Node, Python, Docker, Ollama, LM Studio, and local AI workloads appear by name.

### Understand memory pressure

Memory pressure is often a better indicator of system health than RAM usage alone. Thermal Pilot surfaces it prominently alongside a complete breakdown of Active, Wired, Compressed, Cached, and Free memory.

### Know when performance is affected

A built-in slowdown indicator analyzes CPU load, memory pressure, temperatures, and fan activity to explain what's happening in plain English.

### Fully local

No accounts. No analytics. No telemetry. No background services.

Everything runs locally on your Mac using public macOS APIs and hardware sensors.

### Lightweight by design

Lives entirely in your menu bar. No Dock icon. No unnecessary background processes. Fast startup and configurable refresh intervals.

### Built for real hardware

When a sensor isn't available on your Mac, Thermal Pilot tells you. It never invents readings or estimates values it cannot verify.

## What You Can See

### CPU

Current CPU utilization, processor information, and overall system load.

### Memory

Memory usage, memory pressure, memory composition, and the processes consuming the most RAM.

### Temperature

The hottest available thermal sensors across your system with support for Celsius and Fahrenheit.

### Fans

Current fan speeds, operating ranges, and utilization percentages where supported.

### System Health

A simple explanation of whether your Mac is running normally or approaching a bottleneck.

## Privacy

Thermal Pilot never sends data anywhere.

No network traffic. No analytics. No accounts. No tracking.

Your preferences remain stored locally on your Mac.

## Open Source

Thermal Pilot is fully open source under the [MIT License](LICENSE).

Contributions, bug reports, and feature suggestions are welcome.
