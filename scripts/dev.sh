#!/bin/sh
set -euo pipefail

APP_NAME="AgentBuffer"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/AgentBuffer.app"
APP_ID="com.agentbuffer.AgentBuffer"
SLEEP_SECONDS=0.5
WATCH_MODE="false"
BUNDLE_MODE="false"
USE_OPEN="true"
APP_PID=""
APP_EXPECTED="false"

wait_for_app_pid() {
    APP_PID=""
    i=0
    while [ "$i" -lt 50 ]; do
        pid="$(pgrep -x "$APP_NAME" 2>/dev/null | head -n 1 || true)"
        if [ -n "$pid" ]; then
            APP_PID="$pid"
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

app_is_running() {
    if [ -n "$APP_PID" ]; then
        if kill -0 "$APP_PID" >/dev/null 2>&1; then
            return 0
        fi
    fi
    pgrep -x "$APP_NAME" >/dev/null 2>&1
}

log() {
    printf '%s\n' "$*" >&2
}

for arg in "$@"; do
    case "$arg" in
        --watch)
            WATCH_MODE="true"
            ;;
        --bundle)
            BUNDLE_MODE="true"
            ;;
        --open)
            USE_OPEN="true"
            ;;
        --no-open)
            USE_OPEN="false"
            ;;
        *)
            ;;
    esac
done

build_app() {
    if [ "$BUNDLE_MODE" = "true" ]; then
        if ! swift build -c release; then
            log "Build failed. Waiting for the next change..."
            return 1
        fi
    else
        if ! swift build; then
            log "Build failed. Waiting for the next change..."
            return 1
        fi
    fi
    return 0
}

hash_inputs() {
    find Sources Package.swift -type f \( -name "*.swift" -o -name "*.svg" -o -name "Package.swift" \) -print0 \
        | xargs -0 stat -f "%m %N" \
        | LC_ALL=C sort \
        | shasum \
        | awk '{print $1}'
}

restart_app() {
    APP_PID=""
    if [ "$WATCH_MODE" = "true" ]; then
        if ! build_app; then
            APP_EXPECTED="false"
            return 1
        fi
    fi
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        pkill -x "$APP_NAME"
        sleep 0.2
    fi
    if [ "$USE_OPEN" = "true" ]; then
        open -ga "$APP_NAME" >/dev/null 2>&1 || true
        osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
        sleep 0.2
    fi
    if [ "$BUNDLE_MODE" = "true" ]; then
        if [ "$WATCH_MODE" = "true" ]; then
            if ! "$ROOT_DIR/scripts/package_app.sh" --skip-build; then
                log "Packaging failed. Waiting for the next change..."
                APP_EXPECTED="false"
                return 1
            fi
        else
            "$ROOT_DIR/scripts/package_app.sh"
        fi
        if [ "$USE_OPEN" = "true" ]; then
            launchctl setenv AGENTBUFFER_DEV 1
            if [ "$WATCH_MODE" = "true" ]; then
                open -n "$APP_DIR" &
                if ! wait_for_app_pid; then
                    log "App failed to launch. Waiting for the next change..."
                    APP_EXPECTED="false"
                    return 1
                fi
            else
                open -n "$APP_DIR"
            fi
        else
            if [ "$WATCH_MODE" = "true" ]; then
                AGENTBUFFER_DEV=1 "$APP_DIR/Contents/MacOS/AgentBuffer" &
                APP_PID="$!"
                sleep 0.1
                if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
                    log "App failed to launch. Waiting for the next change..."
                    APP_EXPECTED="false"
                    return 1
                fi
            else
                AGENTBUFFER_DEV=1 "$APP_DIR/Contents/MacOS/AgentBuffer"
            fi
        fi
    else
        if [ "$WATCH_MODE" = "true" ]; then
            AGENTBUFFER_DEV=1 "$ROOT_DIR/.build/debug/AgentBuffer" &
            APP_PID="$!"
            sleep 0.1
            if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
                log "App failed to launch. Waiting for the next change..."
                APP_EXPECTED="false"
                return 1
            fi
        else
            AGENTBUFFER_DEV=1 swift run
        fi
    fi
    APP_EXPECTED="true"
}

if [ "$WATCH_MODE" = "true" ]; then
    last_hash="$(hash_inputs)"
    if ! restart_app; then
        log "Watching for changes..."
    fi
    while true; do
        if [ "$APP_EXPECTED" = "true" ] && ! app_is_running; then
            exit 0
        fi
        current_hash="$(hash_inputs)"
        if [ "$current_hash" != "$last_hash" ]; then
            last_hash="$current_hash"
            if ! restart_app; then
                log "Watching for changes..."
            fi
        fi
        sleep "$SLEEP_SECONDS"
    done
else
    restart_app
fi
