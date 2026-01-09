# Product Context

## Why This Project Exists
Running multiple coding agents in parallel creates unpredictable completion times and frequent audio interruptions. AgentBuffer replaces that interrupt-driven workflow with an ambient, glanceable pressure gauge in the macOS menu bar.

## Problems It Solves
- Reduces context switches caused by audio completion alerts
- Externalizes the mental bookkeeping of tracking many agent tabs
- Scales to more concurrent agents without increasing cognitive load
- Replaces terminal bell alerts with a single, threshold-based sound + notification cue

## How It Should Work
The app reads Codex session logs to infer running and finished states. It shows the running/total ratio and uses a continuous white→yellow→red color scale for the menu bar icon to express pressure, where more running agents means better (whiter) pressure. The popover groups agents into Running, Idle, and History sections with subtle headers; agent cards show a wrapped, monospaced type badge and a clipped task title. It can also play a sound and send a macOS notification when the idle share crosses a configurable threshold.

## User Experience Goals
- Ambient and readable at a glance
- Simple, predictable signals without false precision
- Opt-in interaction only for basic details
