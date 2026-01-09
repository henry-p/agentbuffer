#!/bin/sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/Sources/AgentBuffer/Resources/metrics-web"
TS_FILE="$WEB_DIR/app.ts"
JS_FILE="$WEB_DIR/app.js"
TS_CONFIG="$WEB_DIR/tsconfig.json"
TSC_BIN="$ROOT_DIR/node_modules/.bin/tsc"

if [ ! -f "$TS_FILE" ]; then
    exit 0
fi

needs_build="false"
if [ ! -f "$JS_FILE" ]; then
    needs_build="true"
elif [ "$TS_FILE" -nt "$JS_FILE" ]; then
    needs_build="true"
fi

if [ "$needs_build" != "true" ]; then
    exit 0
fi

if [ ! -f "$TS_CONFIG" ]; then
    echo "Missing TypeScript config: $TS_CONFIG" >&2
    exit 1
fi

if [ ! -x "$TSC_BIN" ]; then
    echo "TypeScript compiler not found. Run 'npm install' to install dev dependencies." >&2
    exit 1
fi

"$TSC_BIN" -p "$TS_CONFIG"

if [ -f "$JS_FILE" ]; then
    if ! head -n 1 "$JS_FILE" | grep -q "Generated from app.ts"; then
        tmp_file="$(mktemp)"
        printf '%s\n' "// Generated from app.ts. Do not edit directly." > "$tmp_file"
        cat "$JS_FILE" >> "$tmp_file"
        mv "$tmp_file" "$JS_FILE"
    fi
fi
