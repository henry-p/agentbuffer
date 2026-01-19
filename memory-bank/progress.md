# Progress

## Current Status
- Menu bar queue icon with white-to-yellow-to-red gradient; shimmer when agents are running and blink when idle threshold is exceeded or no agents are detected
- Status item title shows running/total with a bouncing dot spinner; tooltip includes total + percent
- Popover main view with pause toggle, summary line + efficiency info icon, Running/Idle/History sections, Load more for history, and footer actions (Metrics, Settings, Quit)
- Agent cards show OpenAI/Anthropic logo badges (fallback to monospaced text), clipped titles, and runtime bars for running agents
- Agent cards are clickable with hover highlight to focus the owning terminal tab (requires Automation permission)
- Efficiency info popover renders a thumb gauge tinted/rotated by pressure percent with contextual messaging
- Settings popover uses glass styling and accordion sections (Alerts/Privacy/Developer) with crossfade transitions
- Alerts include idle threshold slider with snap points + double-click reset, notifications toggle, and sound mode segmented control with system-availability gating and notes
- Privacy includes telemetry toggle; OpenPanel tracking is low-volume and excludes agent titles, PIDs, and file paths
- Developer tools include force spinner, queue icon override slider, test notification, and simulate agents toggle
- Reads live Codex session logs (pgrep/ps + lsof) and maps latest user/assistant events to running/finished; bootstrap/shell messages are ignored and compaction is treated as completion
- File watcher tracks `.codex/sessions` root + recent year/month/day folders (cap 250) with a 1s polling safety net
- Idle alert notifications can be silent or use macOS system sound; Glass plays in-app sound regardless of notification state
- Notification clicks route to the most recently finished agent tab when available; bundled app required for notification permissions
- Local-only metrics web server + dashboard (1h/24h/7d windows) with utilization, response time, idle-over-threshold, throughput, bottleneck, rework, fragmentation, and long-tail runtime; discovery file stored in Application Support
- Single-instance lock, dev logging on state or PID changes, and packaging scripts for bundled app

## Next Steps
- Add additional agent integrations beyond Codex
