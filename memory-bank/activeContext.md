# Active Context

## Current Focus
- Maintain reliable Codex session detection and numerator updates
- Keep the menu bar UI minimal (ratio, queue icon gradient + shimmer, bounce dot)
- Keep file watching with a 1s polling safety net for refreshes
- Maintain dev settings for spinner and queue icon override
- Maintain the popover agent list sections (Idle/Running/History) and subtle headers

## Current Behavior
- Queue icon uses a continuous white-to-yellow-to-red gradient based on running/total (inverted: more running = whiter) with a shimmer pass when agents are running
- 0/0 is treated as a neutral idle state with a white queue icon
- Status text shows running/total plus a dot spinner (idle when nothing is running, bouncing while running or forced)
- Popover shows Idle/Running/History sections with small grey headers
- Pause button beside the main headline toggles animation pause; paused dims the menu bar icon and suppresses idle alerts
- Running/Idle/History cards use the latest non-bootstrap user message clipped to a single-line title
- Agent badges use logo glyphs for known agents (OpenAI/Anthropic) with a monospaced text fallback
- Running cards show runtime values and a thin runtime bar scaled to the longest-running agent; list is sorted by longest runtime
- Idle agents are derived from finished sessions; History shows recent finished transitions with a Load more option
- Plays a sound + macOS notification when idle share crosses a configurable threshold (>=) after being below it; no alert on launch if already above
- Popover includes summary/suggestion, the agent list sections, and footer actions (Settings, Quit); Test Notification lives in Developer settings
- Settings live as a single page inside the same popover with accordion section headers (Alerts/Privacy/Developer) that expand/collapse; Done exits settings
- Permission prompts show a brief floating window to ensure the app is active
- File watcher tracks the `.codex/sessions` tree and caps watches to the 250 most recent day folders
- Codex session parsing scans backward from log tails to find the latest user/assistant events
- Compaction log events are emitted only after completion, so they are treated as finished (assistant) to avoid a post-compaction "running" blip
- Refresh work runs off the main thread; menu bar stays responsive
- Dev logging emits only on state changes or PID-set changes
- Dev watch script exits when the app is manually closed
- Agent cards are clickable across all sections with hover highlights and pointing-hand cursor
- Notification clicks route to the most recently finished agent tab when available
- Settings use a System Settings-style grouped list with row separators, accordion headers, left labels, and right-aligned controls (switches, sliders, and action buttons)
- Settings include notifications toggle plus a sound mode selector (Off/Glass/System) with System gated by macOS notification sound availability
- Telemetry events are sent through OpenPanel when enabled, with app-lifecycle auto tracking via the proxy endpoint
- Telemetry covers UI interactions and low-volume state transitions without collecting agent titles, PIDs, or file paths
- Terminal tab focus uses PID→TTY lookup and AppleScript automation (iTerm2/Terminal)
- Settings interaction uses switch controls instead of checkbox rows
- Popover and notification prompt use a glass material background (no legacy fallback); settings groups are transparent with separators to avoid glass stacking
- Settings ↔ main page transitions use a short crossfade for a more fluid feel
- Settings accordion sections expand/collapse in place with a single rounded container border and a short animation (no topic/detail navigation)
- Local-only Swift metrics web service runs in-process, serving a metrics dashboard and JSON endpoints from bundled resources; discovery info is written in Application Support.

## Next Steps
- Add additional agent integrations (e.g., Claude Code)

## Decisions & Considerations
- Standard mode only
- Task boundaries rely on agent-specific integrations
- No reliable "compaction started" signal exists in Codex logs; only completion is logged
