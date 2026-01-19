# Product Context

## Why This Project Exists
Running multiple coding agents in parallel creates unpredictable completion times and frequent audio interruptions. AgentBuffer replaces that interrupt-driven workflow with an ambient, glanceable pressure gauge in the macOS menu bar and a local metrics view for deeper operator feedback.

## Problems It Solves
- Reduces context switches caused by audio completion alerts
- Externalizes the mental bookkeeping of tracking many agent tabs
- Scales to more concurrent agents without increasing cognitive load
- Replaces terminal bell alerts with a single, threshold-based sound + notification cue
- Surfaces operator bottlenecks (response time, idle over threshold) without adding instrumentation

## How It Should Work
The app reads Codex session logs for live Codex processes and infers running/finished states from the latest user/assistant events (ignoring bootstrap and shell-command messages). It shows the running/total ratio and uses a continuous white → yellow → red color scale for the menu bar icon, where more running agents means better (whiter) pressure. The popover groups agents into Idle, Running, and History sections; running cards include runtime bars and all cards are clickable to refocus the owning terminal tab. The summary row includes an info icon that opens an "Efficiency" view, and the footer exposes Metrics (local dashboard), Settings, and Quit. Idle alerts can play a sound and send a macOS notification when the idle share crosses a configurable threshold. A local-only metrics server powers a dashboard and JSON endpoints covering utilization, response time, idle-over-threshold, throughput, and quality guardrails.

## User Experience Goals
- Ambient and readable at a glance
- Simple, predictable signals without false precision
- Optional deeper diagnostics without cluttering the menu bar UI
- Local-first: metrics stay on-device; telemetry is opt-out and low volume
