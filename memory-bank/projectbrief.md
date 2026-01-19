# Project Brief

## Overview
AgentBuffer is a macOS menu bar app that acts as a pressure gauge for parallel coding agents. It reads live Codex session logs, computes a running/total ratio, colors the menu bar icon along a white → yellow → red gradient, and exposes a compact popover plus an optional local metrics dashboard for deeper operational visibility.

## Goals
- Provide a stable, ambient signal for running vs idle agent pressure
- Replace noisy "done" alerts with state-based visuals and a single idle-threshold alert
- Keep the core model simple (running/total ratio) while offering optional diagnostic metrics
- Enable one-click focus back to the owning terminal tab when needed

## Scope
- macOS menu bar app with a popover UI (main, settings, efficiency info)
- Read Codex session logs for live processes; infer running/idle states and runtimes
- Idle-threshold alerts with optional sound + notification
- Local-only metrics web server and dashboard with JSON endpoints
- Optional, low-volume telemetry gated by Settings

## Non-Goals
- Per-agent deep-dive dashboards or task-level analytics
- Progress prediction, scheduling, or agent orchestration
- Cloud services or cross-platform support
- High-frequency notifications or per-agent alerting
