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
- Running/Idle/History cards use the latest non-bootstrap user message clipped to a single-line title
- Agent badges use logo glyphs for known agents (OpenAI/Anthropic) with a monospaced text fallback
- Running cards show runtime values and a thin runtime bar scaled to the longest-running agent; list is sorted by longest runtime
- Idle agents are derived from finished sessions; History shows recent finished transitions with a Load more option
- Plays a sound + macOS notification when idle share crosses a configurable threshold (>=) after being below it; no alert on launch if already above
- Popover includes summary/suggestion, the agent list sections, and footer actions (Settings, Quit); Test Notification lives in Developer settings
- Settings live as a second page inside the same popover with a topics list and per-topic detail view (Back returns to topics; Done exits settings)
- Permission prompts show a brief floating window to ensure the app is active
- File watcher tracks the `.codex/sessions` tree and caps watches to the 250 most recent day folders
- Codex session parsing scans backward from log tails to find the latest user/assistant events
- Compaction log events are emitted only after completion, so they are treated as finished (assistant) to avoid a post-compaction "running" blip
- Refresh work runs off the main thread; menu bar stays responsive
- Dev logging emits only on state changes or PID-set changes
- Dev watch script exits when the app is manually closed
- Agent cards are clickable across all sections with hover highlights and pointing-hand cursor
- Notification clicks route to the most recently finished agent tab when available
- Settings use a System Settings-style grouped list with row separators, chevrons for topics, left labels, and right-aligned controls (switches, sliders, and action buttons)
- Settings include idle alert sound, notifications, and telemetry switches (default on)
- Telemetry events are sent through OpenPanel when enabled, with app-lifecycle auto tracking via the proxy endpoint
- Telemetry covers UI interactions and low-volume state transitions without collecting agent titles, PIDs, or file paths
- Terminal tab focus uses PID→TTY lookup and AppleScript automation (iTerm2/Terminal)
- Settings interaction uses switch controls instead of checkbox rows

## Next Steps
- Add additional agent integrations (e.g., Claude Code)

## Decisions & Considerations
- Standard mode only
- Task boundaries rely on agent-specific integrations
- No reliable "compaction started" signal exists in Codex logs; only completion is logged
