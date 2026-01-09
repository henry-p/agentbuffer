# Project Brief

## Overview
AgentBuffer is a macOS menu bar app that gives a glanceable, ambient view of parallel coding agents by acting as a pressure gauge for workload: it shows running/total progress and colors the menu bar icon on a white→yellow→red gradient based on the running ratio.

## Goals
- Provide a stable, ambient pressure gauge for how many agents are running
- Replace audio interruptions with state-based visual cues
- Keep the model simple and predictable with a running/total ratio
- Provide a single, configurable idle-threshold sound + notification alert (optional)

## Scope
- macOS menu bar app
- Read agent state from Codex session logs
- Compute running/total ratio and map to a continuous color scale
- Show details in a small menu with no per-agent drill-down

## Non-Goals
- Per-agent detail views or dashboards
- Progress bars, predictions, or scheduling
- Frequent notifications or per-agent alerts
- Expert mode weighting or structured metadata ingestion
