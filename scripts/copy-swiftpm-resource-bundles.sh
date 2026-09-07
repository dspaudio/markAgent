#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: copy-swiftpm-resource-bundles.sh <build-products-dir> <app-bundle-dir>" >&2
    exit 64
fi

BUILD_PRODUCTS_DIR="$1"
APP_BUNDLE_DIR="$2"
APP_RESOURCES_DIR="$APP_BUNDLE_DIR/Contents/Resources"

mkdir -p "$APP_RESOURCES_DIR"
for resource_bundle in "$BUILD_PRODUCTS_DIR"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    cp -R "$resource_bundle" "$APP_RESOURCES_DIR/"
done
