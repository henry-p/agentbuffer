# Active Context

## Current Focus
- Maintain reliable Codex session detection (pgrep/ps + lsof) and log-tail parsing with bootstrap/shell filtering
- Keep the menu bar UI minimal (ratio, queue icon gradient + shimmer + idle blink, bouncing dot)
- Keep file watching for `.codex/sessions` with a 1s polling safety net
- Maintain popover flows (main, settings, efficiency info) with glass styling and crossfades
- Keep alerts, sound availability gating, and notification permission flow stable
- Maintain local metrics dashboard + developer tooling (simulation, overrides)

## Current Behavior
- Queue icon uses a continuous white-to-yellow-to-red gradient based on running/total (more running = whiter) with shimmer when agents are running and blink when idle threshold is exceeded or no agents are detected
- Status text shows running/total plus a bouncing dot spinner; paused state dims the icon and suppresses animations/alerts
- Refresh loop uses a background queue plus a file watcher on `.codex/sessions` (root + recent year/month/day dirs, capped at 250) and a 1s polling fallback
- Codex session parsing scans log tails for the latest user/assistant events, ignores bootstrap + shell-command messages, uses session meta instructions to filter, and treats compaction as assistant completion
- Running list is sorted by longest runtime; runtime bars scale to the longest-running agent; idle list is derived from finished sessions; History shows recent finished transitions with Load more
- Agent cards show OpenAI/Anthropic logo badges (fallback to monospaced text) and clipped task titles; cards are clickable across sections with hover highlights and pointer cursor
- Main popover includes a pause button, summary row with an Efficiency info icon, Idle/Running/History sections, and footer actions (Metrics, Settings, Quit)
- Efficiency popover shows a thumb gauge tinted to the pressure color, rotated by utilization, and a short contextual message
- Settings popover uses accordion sections (Alerts/Privacy/Developer) with crossfade transitions and glass styling; Alerts include idle threshold slider with snap points + double-click reset, notification toggle, and sound mode segmented control with system availability notes; Privacy includes telemetry toggle; Developer includes force spinner, queue icon override slider, test notification, and simulate agents
- Idle alert triggers on threshold crossings after being below it (or rising idle after launch), plays Glass/System sound based on availability, and posts a notification containing the most recent finished PID for click-to-focus
- Notification permission flow shows a brief glass prompt window to ensure the app is active before requesting access
- Local-only metrics web server runs in-process (127.0.0.1, auto-incremented port) serving a dashboard and `/api/summary`, `/api/timeseries`, `/api/health`; discovery info is written to Application Support
- Metrics compute utilization, response time (median/p90), idle-over-threshold minutes, throughput, task supply rate, bottleneck index, rework rate, fragmentation, and long-tail runtime from session logs
- Telemetry events are sent through OpenPanel via proxy when enabled; opt-in/out always allowed; no agent titles, PIDs, or file paths collected
- Terminal tab focus uses PID→TTY lookup and AppleScript automation (iTerm2/Terminal); notification clicks focus the most recently finished agent
- Single-instance lock prevents multiple running app instances; dev logging emits only on state/PID changes and dev watch exits when the app is manually closed

## Next Steps
- Add additional agent integrations (e.g., Claude Code)

## Decisions & Considerations
- Standard mode only; no predictions or scheduling
- Metrics are local-only and derived from existing session logs
- Task boundaries rely on agent-specific integrations
- No reliable "compaction started" signal exists in Codex logs; only completion is logged
