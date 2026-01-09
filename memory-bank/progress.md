# Progress

## Current Status
- Menu bar app with queue icon, ratio text, dot spinner, and a shimmer pass while agents run
- Unified popover UI with main status page and settings page
- Queue icon tint follows a continuous white-to-yellow-to-red gradient based on running/total (inverted so more running is whiter)
- 0/0 state shows a white queue icon (neutral idle)
- Reads active Codex session logs and maps latest user/assistant events to running/finished
- File watcher on `.codex/sessions` with a cap of 250 recent day folders
- 1s polling safety net alongside file watching
- Configurable idle alert threshold plus sound mode (Off/Glass/System) with System gated by macOS notification sound availability
- Test Notification action in Developer settings
- Popover shows Idle/Running/History sections with subtle headers
- Pause control next to the headline halts menu bar animations and suppresses idle alerts while paused
- Agent cards use logo badges for known agents with monospaced text fallback, plus clipped task titles
- Running agent cards show runtime values and a thin runtime bar; running list is sorted by longest runtime
- Idle agents list is derived from finished sessions; History shows recent finished transitions with Load more
- Agent cards are clickable with hover highlight to jump to the owning terminal tab when possible (requires Automation permission)
- Agent card clicks work across all sections (Running/Idle/History) via container-level hit testing
- Idle alert notifications link back to the most recently finished agent tab
- Idle alert notifications can be silent or use the macOS system sound; Glass plays the in-app sound regardless of notification state
- Telemetry is sent via OpenPanel with app-lifecycle auto tracking and a Settings toggle (default on)
- Telemetry captures UI interactions (popover/settings/buttons) and state transitions (agent counts, idle alerts, notifications) without PII
- Settings UI matches macOS System Settings style with accordion section headers, grouped rows, separators, and switch/slider controls
- Popover and notification prompt use a glass material background; settings groups avoid opaque fills to prevent glass stacking
- Popover main/settings transitions crossfade to match the Liquid Glass feel
- Settings accordion sections expand/collapse in place with a unified rounded container border and animation
- Local-only Swift metrics web service runs in-process, serving a metrics dashboard and JSON endpoints from bundled resources
- Dev settings (force spinner, queue icon override toggle + slider) gated by the dev script
- Single-instance lock
- App bundle packaging script (codesigned for notification permissions)
- Dev logging on state or PID changes
- Compaction log events are treated as finished (no running state after completion)

## Next Steps
- Add additional agent integrations beyond Codex
