#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: patch-libghostty-resource-bundle.sh <libghostty-spm-checkout>" >&2
    exit 64
fi

CHECKOUT_DIR="$1"
EXPECTED_REVISION="356f730bec03281fc7b83666a129b0246137ea26"
PATCHED_SOURCE="$(cd "$(dirname "$0")" && pwd)/patches/GhosttyRuntimeResources.swift"
TARGET_SOURCE="$CHECKOUT_DIR/Sources/GhosttyTerminal/Configuration/GhosttyRuntimeResources.swift"
ACTUAL_REVISION="$(git -C "$CHECKOUT_DIR" rev-parse HEAD)"

if [ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]; then
    echo "error: unsupported libghostty-spm revision: $ACTUAL_REVISION" >&2
    exit 1
fi

cp -f "$PATCHED_SOURCE" "$TARGET_SOURCE"
