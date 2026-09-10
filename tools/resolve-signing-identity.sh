#!/bin/sh
set -eu

env_file=${1:-}

if [ -n "${LITTLE_SWITCH_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$LITTLE_SWITCH_SIGN_IDENTITY"
    exit 0
fi

if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
    printf '%s\n' "$APPLE_SIGNING_IDENTITY"
    exit 0
fi

if [ ! -f "$env_file" ]; then
    exit 0
fi

/usr/bin/awk '
    /^[[:space:]]*APPLE_SIGNING_IDENTITY[[:space:]]*=/ {
        value = $0
        sub(/^[^=]*=[[:space:]]*/, "", value)
        sub(/[[:space:]]*$/, "", value)

        first = substr(value, 1, 1)
        last = substr(value, length(value), 1)
        if (length(value) >= 2 && ((first == "\"" && last == "\"") || (first == "\047" && last == "\047"))) {
            value = substr(value, 2, length(value) - 2)
        }

        print value
        exit
    }
' "$env_file"
