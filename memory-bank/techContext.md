# Tech Context

## Technologies Used
- Swift 5.9
- AppKit for macOS menu bar UI
- DispatchSource for filesystem events
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
- Telemetry sends network requests only when enabled

## Dependencies
- OpenPanel Swift SDK (vendored in `Vendor/OpenPanel` for macOS build compatibility)
- OpenPanel relay proxy (HTTPS) for client telemetry
