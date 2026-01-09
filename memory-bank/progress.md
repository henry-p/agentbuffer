# Progress

## Current Status
- Menu bar app with queue icon, ratio text, dot spinner, and a shimmer pass while agents run
- Unified popover UI with main status page and settings page
- Queue icon tint follows a continuous white-to-yellow-to-red gradient based on running/total (inverted so more running is whiter)
- 0/0 state shows a white queue icon (neutral idle)
- Reads active Codex session logs and maps latest user/assistant events to running/finished
- File watcher on `.codex/sessions` with a cap of 250 recent day folders
- 1s polling safety net alongside file watching
- Configurable idle alert sound + notification threshold with threshold-crossing semantics
- Test Notification action in Developer settings
- Popover shows Idle/Running/History sections with subtle headers
- Agent cards use logo badges for known agents with monospaced text fallback, plus clipped task titles
- Running agent cards show runtime values and a thin runtime bar; running list is sorted by longest runtime
- Idle agents list is derived from finished sessions; History shows recent finished transitions with Load more
- Agent cards are clickable with hover highlight to jump to the owning terminal tab when possible (requires Automation permission)
- Agent card clicks work across all sections (Running/Idle/History) via container-level hit testing
- Idle alert notifications link back to the most recently finished agent tab
- Idle alert in-app sound and notification visibility are toggleable in Settings; in-app sound is skipped when system notification sound is enabled
- Telemetry is sent via OpenPanel with app-lifecycle auto tracking and a Settings toggle (default on)
- Telemetry captures UI interactions (popover/settings/buttons) and state transitions (agent counts, idle alerts, notifications) without PII
- Settings UI matches macOS System Settings style with a topics list, grouped rows, separators, and switch/slider controls
- Dev settings (force spinner, queue icon override toggle + slider) gated by the dev script
- Single-instance lock
- App bundle packaging script (codesigned for notification permissions)
- Dev logging on state or PID changes
- Compaction log events are treated as finished (no running state after completion)

## Next Steps
- Add additional agent integrations beyond Codex
