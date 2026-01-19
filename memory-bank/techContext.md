# Tech Context

## Technologies Used
- Swift 5.9
- AppKit for macOS menu bar UI (NSStatusItem, popovers, NSVisualEffectView)
- UserNotifications for alerts
- DispatchSource + Timer for filesystem events/polling
- Network framework (NWListener) for the local metrics server
- CoreImage for efficiency thumb colorization
- AppleScript automation for Terminal/iTerm2 focus
- HTML/CSS/TypeScript (compiled to JS) for the metrics dashboard UI
- Swift Package Manager
- OpenPanel Swift SDK (telemetry)

## Development Setup
- Build with `swift build -c release`
- Run the executable from `.build/release/AgentBuffer`
- Dev script: `./scripts/dev.sh` (sets `AGENTBUFFER_DEV=1` for dev settings); `--bundle` launches via LaunchServices by default (needed for notifications), `--no-open` disables it, and watch mode builds before relaunching and runs `.build/debug/AgentBuffer`
- Packaging script `./scripts/package_app.sh` codesigns the app bundle (adhoc) so macOS notification permissions can be requested and supports `--skip-build`
- Terminal focus requires running the app as a bundle so macOS Automation permission prompts appear

## Technical Constraints
- macOS 13 or newer
- Notifications/system sound availability depend on bundle mode + OS permissions
- Metrics server binds to 127.0.0.1 and auto-increments port if busy
- Telemetry sends network requests only when enabled

## Dependencies
- OpenPanel Swift SDK (vendored in `Vendor/OpenPanel` for macOS build compatibility)
- OpenPanel relay proxy (HTTPS) for client telemetry
