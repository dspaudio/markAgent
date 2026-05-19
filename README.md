# MarkAgent

**The Professional GUI for your CLI AI Agents.**

MarkAgent is a native macOS Markdown editor and viewer designed to sit next to CLI-based AI agents such as Codex CLI, Claude Code, and Gemini CLI. It opens Markdown files from the terminal, renders GitHub Flavored Markdown, supports raw editing, and provides a terminal-centered workspace for agent-driven development.

MarkAgent는 Codex CLI, Claude Code, Gemini CLI 같은 CLI 기반 AI 에이전트와 함께 쓰기 위한 macOS 네이티브 마크다운 에디터/뷰어입니다. 터미널에서 마크다운 파일을 열고, GitHub Flavored Markdown을 렌더링하며, 원문 편집과 터미널 중심 워크스페이스를 제공합니다.

## Features

- Native macOS app bundle with Dock, menu bar, Cmd+Tab, and window behavior.
- Markdown preview and raw edit modes.
- GitHub Flavored Markdown rendering with tables, task lists, and strikethrough.
- Syntax-highlighted code blocks.
- Recent document sidebar and file browser.
- Terminal tabs powered by `libghostty-spm`.
- Inline diff view for changed Markdown content.
- Optional Always on Top mode, disabled by default.

## 주요 기능

- Dock, 메뉴바, Cmd+Tab, 윈도우 동작을 지원하는 macOS 네이티브 앱 번들.
- 마크다운 미리보기와 원문 편집 모드.
- 표, 체크리스트, 취소선을 포함한 GitHub Flavored Markdown 렌더링.
- 코드 블록 구문 하이라이팅.
- 최근 문서 사이드바와 파일 브라우저.
- `libghostty-spm` 기반 터미널 탭.
- 변경된 마크다운 내용을 확인하는 인라인 Diff.
- 선택적으로 켤 수 있는 Always on Top 모드. 기본값은 꺼져 있습니다.

## Requirements

- macOS 14 Sonoma or later
- Swift 6.0 or later for building from source

## 요구 사항

- macOS 14 Sonoma 이상
- 소스에서 빌드할 경우 Swift 6.0 이상

## Build

```bash
swift build
```

Create a macOS app bundle:

```bash
scripts/bundle.sh
```

Create a release bundle:

```bash
scripts/bundle.sh release
```

Install to `~/Applications` and link the `ma` CLI when possible:

```bash
scripts/bundle.sh install
```

## 빌드

```bash
swift build
```

macOS 앱 번들 생성:

```bash
scripts/bundle.sh
```

릴리스 번들 생성:

```bash
scripts/bundle.sh release
```

`~/Applications`에 설치하고 가능한 경우 `ma` CLI 링크 생성:

```bash
scripts/bundle.sh install
```

## Usage

Open a Markdown file through the app bundle:

```bash
open .build/MarkAgent.app --args README.md
```

Or run the CLI binary after building:

```bash
.build/debug/ma README.md
```

## 사용법

앱 번들을 통해 마크다운 파일 열기:

```bash
open .build/MarkAgent.app --args README.md
```

빌드 후 CLI 바이너리로 실행:

```bash
.build/debug/ma README.md
```

## Open Source

MarkAgent uses the following open source libraries:

- `swift-markdown` - Apache-2.0
- `swift-cmark` - BSD-style and MIT notices
- `HighlightSwift` - MIT, including `highlight.js` under BSD-3-Clause
- `libghostty-spm` - MIT, bundling `libghostty` under its own license terms
- `MSDisplayLink` - MIT

## 오픈소스

MarkAgent는 다음 오픈소스 라이브러리를 사용합니다.

- `swift-markdown` - Apache-2.0
- `swift-cmark` - BSD-style and MIT notices
- `HighlightSwift` - MIT, 내부 `highlight.js`는 BSD-3-Clause
- `libghostty-spm` - MIT, 포함된 `libghostty`는 자체 라이선스 조건 적용
- `MSDisplayLink` - MIT

## Repository

https://github.com/dspaudio/markAgent
