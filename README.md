# AgentBuffer

A macOS menu bar app that shows an ambient view of parallel coding agents.

## Build and Run

```sh
swift build -c release
./.build/release/AgentBuffer
```

## Build App Bundle

```sh
./scripts/package_app.sh
open dist/AgentBuffer.app
```

## Codex Support

AgentBuffer reads Codex session logs from `~/.codex/sessions` for currently running Codex processes and treats each active session as an agent. The most recent user message marks that session as running; the most recent assistant message marks it as finished. Old sessions without a live process are ignored.

## UI Details

The menu bar item shows a small icon to the left of the status text. The icon is bundled from `Sources/AgentBuffer/Resources/queue.svg` and scaled to fit the menu bar height with padding.

## License

GNU GPLv3. See `LICENSE`.
