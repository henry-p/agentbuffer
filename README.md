# AgentBuffer

AgentBuffer is a macOS menu bar **pressure gauge** for parallel coding agents. It trades noisy "done" alerts for a calm, glanceable signal so you can keep many agents moving without losing focus.

## Highlights

- Ambient queue icon that fades **white -> yellow -> red** as the running ratio drops (more running = whiter).
- Popover with Running / Idle / History sections, runtimes, and one-click focus back to your terminal tab.
- Idle-threshold alerts with optional sound + notification.
- Local-only metrics dashboard with utilization, response time, throughput, and idle-over-threshold.
- Zero setup beyond running Codex: it reads `~/.codex/sessions` and infers status from logs.

## Quick Start (Run It)

```sh
./scripts/package_app.sh
open dist/AgentBuffer.app
```

Start or continue Codex sessions and the menu bar item updates automatically.

## How It Works

1. Finds live Codex processes and their session logs in `~/.codex/sessions`.
2. Treats the latest **user** event as "running" and the latest **assistant** event as "finished."
3. Computes the running/total ratio, drives the menu bar tint, and shows details in the popover.

## Requirements

- macOS 13+
- Swift 5.9 (Xcode Command Line Tools)
- Codex CLI (sessions written to `~/.codex/sessions`)

## Install From Source

```sh
swift build -c release
./.build/release/AgentBuffer
```

For notifications and terminal-focus integration, run the **app bundle**:

```sh
./scripts/package_app.sh
open dist/AgentBuffer.app
```

## Settings & Behavior

AgentBuffer keeps the UI minimal and predictable:

- **Idle alert threshold** (default 50%) with optional sound + notification.
- **Sound modes**: Off, Glass (in-app), or System (uses macOS notification sound).
- **Telemetry** toggle in Settings -> Privacy (see below).
- **Developer mode** (set `AGENTBUFFER_DEV=1`) enables test tools and visual overrides.

## Metrics Dashboard (Local-Only)

AgentBuffer runs a tiny local web server and serves a metrics UI and JSON endpoints.

- Default port starts at **48900** and auto-increments if busy.
- The active port is written to:
  `~/Library/Application Support/AgentBuffer/metrics-server.json`

Open the dashboard in your browser:

```sh
open "http://127.0.0.1:48900"
```

If the port changed, check the discovery file for the current value.

## Privacy & Telemetry

Telemetry is **optional** (enabled by default) and can be disabled in Settings -> Privacy. When enabled, it sends low-volume UI and state events (counts, toggles, basic app metadata) via OpenPanel. It does **not** transmit agent titles, file paths, or session contents.

## Development

```sh
./scripts/dev.sh --watch
```

Useful flags:

- `--bundle` : runs the app as a .app bundle (required for notifications & Automation prompts)
- `--no-open` : runs without `open`/LaunchServices

## FAQ

**No agents detected?**  
AgentBuffer only counts **live Codex processes** with active session logs. Make sure Codex is running and writing to `~/.codex/sessions`.

**Clicking an agent doesn't focus my terminal.**  
Focusing requires macOS Automation permissions for Terminal or iTerm2. Run the app bundle and allow access when prompted.

## License

GNU GPLv3. See `LICENSE`.
