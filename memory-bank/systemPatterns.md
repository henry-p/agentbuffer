# System Patterns

## Architecture
- Codex session logs -> StatusReader -> StatusEvaluator -> StatusSnapshot -> Menu bar UI + Popover
- Codex session logs -> MetricsEngine -> MetricsWebServer -> local metrics dashboard + JSON API

## Key Technical Decisions
- Use Codex session logs as the primary integration for least setup
- Only count Codex sessions that belong to running Codex processes (pgrep/ps + lsof), using the most recent log per PID
- Classify running vs finished by latest user/assistant event; ignore bootstrap/shell messages and treat compaction as completion
- Compute a running/total ratio and map it to a continuous color gradient; shimmer when running and blink when idle threshold is exceeded
- Keep UI as a menu bar item backed by a single popover with main/settings/info views and crossfade transitions
- Gate dev-only controls via an environment flag
- Alert only on idle-threshold crossings (>=), primed by a prior below-threshold state, with sound + notification
- Notification permission flow checks current authorization state and uses an app-activation prompt window before requesting
- Telemetry uses OpenPanel with app-lifecycle auto tracking, a settings-gated filter, and an HTTPS proxy endpoint
- Telemetry emits low-volume UI interaction and state transition events; opt-in/out events bypass the settings filter
- Use last user-event timestamps to derive running-agent runtime for sorting and runtime indicators
- Present the status as a pressure gauge for review workload (not a progress tracker)
- Use agent-specific integrations instead of supporting arbitrary commands
- Focus terminal tabs by PID->TTY lookup and AppleScript automation (iTerm2/Terminal), gated by macOS Automation permissions
- Serve a local-only metrics dashboard via an in-process Swift web service bound to the app lifecycle

## Design Patterns
- Data parsing and evaluation are separated from UI updates
- File watching is isolated in a helper class and preferred over polling; watch set includes root + recent year/month/day dirs and is capped to 250 day folders
- Codex session parsing is its own reader module with per-PID trackers and backward log scanning in chunks
- Session logs are scanned backward to find the most recent user/assistant event; ordering defines running vs finished
- Latest non-bootstrap user message is captured to title running/idle/history cards in the popover
- Recent history is built by diffing prior running agents against the current set; UI filters history IDs that are still idle
- Codex compaction logs only show completion; compaction events are classified as finished to avoid a false "running" state after /compact
- Menu bar queue icon shimmer/blink effects are driven by running/idle thresholds to add motion without extra UI
- Agent badges prefer SVG logo glyphs when available, with monospaced text fallback
- Menu bar rendering and popover behavior are extracted into dedicated helpers (MenuBarRenderer, PopoverCoordinator)
- Terminal tab focus is handled in a small navigator utility (TerminalNavigator)
- Agent list click handling is centralized in the list container view to keep card hit-testing consistent across sections
- CursorRectsView centralizes pointing-hand cursor rectangles for interactive controls
- Settings uses accordion sections with hover states and animated height transitions
- Metrics engine caches summaries briefly and derives utilization/response metrics from event segments

## Component Relationships
- AgentBufferApp owns StatusReader and renders StatusSnapshot
- StatusReader feeds Codex session states into evaluation
- StatusEvaluator computes progressPercent from running/total
- StatusSnapshot carries runningAgents and idleAgents; recent history is tracked separately from running/idle
- MenuBarRenderer owns status item drawing, shimmer/blink effects, and spinner state
- PopoverCoordinator owns popover window + controller switching and click-outside handling
- MainPopoverController renders the agent sections and footer actions
- SettingsPopoverController manages Alerts/Privacy/Developer accordion state
- InfoPopoverController renders the efficiency thumb gauge
- TerminalNavigator resolves PID->TTY and activates iTerm2/Terminal tabs
- MetricsEngine computes metrics from session logs; MetricsWebServer serves the dashboard + API
