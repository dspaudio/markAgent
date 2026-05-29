#!/bin/bash
# MarkAgent.app 번들 생성 스크립트
#
# 사용법:
#   scripts/bundle.sh              # debug 빌드 + 번들 생성
#   scripts/bundle.sh release      # release 빌드 + 번들 생성 + 가능한 경우 Developer ID 서명
#   scripts/bundle.sh install      # release 빌드 + 서명 + ~/Applications 설치 + CLI 심볼릭 링크
#
# 서명 제어:
#   MARKAGENT_CODESIGN=0 scripts/bundle.sh release
#   MARKAGENT_CODESIGN=1 scripts/bundle.sh release  # 서명 ID가 없으면 실패
#   MARKAGENT_SIGN_IDENTITY="Developer ID Application: ..." scripts/bundle.sh release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MarkAgent"

ACTION="${1:-debug}"
if [ "$ACTION" = "install" ]; then
    CONFIG="release"
else
    CONFIG="$ACTION"
fi

BUNDLE_DIR="$PROJECT_DIR/.build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

# 빌드
echo "Building ($CONFIG)..."
swift build -c "$CONFIG" --package-path "$PROJECT_DIR"

# 기존 번들 제거 후 구조 생성
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"

# 실행 파일 및 Info.plist 복사
cp "$PROJECT_DIR/.build/$CONFIG/ma" "$MACOS_DIR/ma"
cp "$PROJECT_DIR/Sources/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/README.md" "$CONTENTS_DIR/Resources/README.md"
if [ -d "$PROJECT_DIR/Sources/App/Resources" ]; then
    cp -R "$PROJECT_DIR/Sources/App/Resources/." "$CONTENTS_DIR/Resources/"
fi

should_codesign() {
    [ "$ACTION" = "release" ] || [ "$ACTION" = "install" ]
}

has_codesign_identity() {
    local identity="$1"
    security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$identity"
}

detect_sign_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' \
        | head -n 1
}

sign_bundle() {
    local identity="${MARKAGENT_SIGN_IDENTITY:-}"

    if [ -z "$identity" ]; then
        identity="$(detect_sign_identity)"
    fi

    if [ "${MARKAGENT_CODESIGN:-auto}" = "0" ]; then
        echo "Code signing skipped (MARKAGENT_CODESIGN=0)."
        return
    fi

    if [ -z "$identity" ]; then
        if [ "${MARKAGENT_CODESIGN:-auto}" = "1" ]; then
            echo "error: Developer ID Application signing identity not found" >&2
            exit 1
        fi

        echo "Code signing skipped: Developer ID Application identity not found."
        return
    fi

    if ! has_codesign_identity "$identity"; then
        if [ "${MARKAGENT_CODESIGN:-auto}" = "1" ]; then
            echo "error: code signing identity not found: $identity" >&2
            exit 1
        fi

        echo "Code signing skipped: identity not found: $identity"
        return
    fi

    echo "Code signing with: $identity"
    codesign --force --options runtime --timestamp --sign "$identity" "$MACOS_DIR/ma"
    codesign --force --options runtime --timestamp --sign "$identity" "$BUNDLE_DIR"
    codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"
    echo "✓ signed $BUNDLE_DIR"
}

if should_codesign; then
    sign_bundle
fi

echo "✓ $BUNDLE_DIR"

# install 모드: ~/Applications로 복사 + CLI 심볼릭 링크
if [ "$ACTION" = "install" ]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
    cp -R "$BUNDLE_DIR" "$INSTALL_DIR/${APP_NAME}.app"
    echo "✓ $INSTALL_DIR/${APP_NAME}.app"

    BIN_DIR="/usr/local/bin"
    if [ -d "$BIN_DIR" ] && [ -w "$BIN_DIR" ]; then
        ln -sf "$INSTALL_DIR/${APP_NAME}.app/Contents/MacOS/ma" "$BIN_DIR/ma"
        echo "✓ $BIN_DIR/ma → ${APP_NAME}.app"
        echo ""
        echo "사용법: ma <filepath>"
    else
        echo ""
        echo "CLI 심볼릭 링크를 수동으로 생성하세요:"
        echo "  sudo ln -sf $INSTALL_DIR/${APP_NAME}.app/Contents/MacOS/ma $BIN_DIR/ma"
    fi
else
    echo ""
    echo "실행: open $BUNDLE_DIR --args <filepath>"
    echo "      .build/$CONFIG/ma <filepath>  (자동 번들 실행)"
fi
