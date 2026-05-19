<p align="center">
  <img src="Sources/App/Resources/AppIcon.png" alt="MarkAgent icon" width="128" height="128">
</p>

# MarkAgent

**Ghostty 기반 멀티탭 터미널과 마크다운 작업 공간을 하나로 묶은 macOS 네이티브 개발 도구.**

MarkAgent는 Codex CLI, Claude Code, Gemini CLI 같은 CLI 기반 AI 에이전트로 개발할 때 필요한 작업 화면을 macOS 앱 안에 모아 둔 도구입니다. Ghostty 터미널 탭에서 에이전트를 실행하고, 같은 창에서 작업 경로의 파일을 확인하며, 에이전트가 생성하거나 수정한 Markdown 문서를 바로 편집하고 미리 볼 수 있습니다.

![MarkAgent 실행 화면](screenshot.png)

## 컨셉

CLI 기반 AI 에이전트는 터미널에서 가장 자연스럽게 동작하지만, 실제 개발 중에는 터미널만으로 부족한 순간이 많습니다. 변경된 파일을 훑어보고, Markdown 결과물을 읽기 좋은 형태로 확인하고, 필요하면 바로 고쳐 저장해야 합니다.

MarkAgent는 이 흐름을 위해 만든 비주얼 브릿지입니다.

- Ghostty 기반 멀티탭 터미널에서 AI 에이전트와 일반 CLI 도구를 실행합니다.
- 작업 경로의 파일 목록을 사이드바에서 확인하고 Markdown 파일을 바로 엽니다.
- Markdown 원문 편집과 GitHub Flavored Markdown 미리보기를 전환합니다.
- Git 변경 파일과 Diff를 앱 안에서 확인해 AI 에이전트의 작업 결과를 추적합니다.
- 터미널 중심 워크플로우는 유지하되, 읽기와 검토가 필요한 화면만 네이티브 GUI로 보강합니다.

## 주요 기능

- **Ghostty 터미널 탭:** `libghostty-spm`을 사용한 내장 터미널 탭으로 여러 작업 세션을 한 창에서 다룹니다.
- **Ghostty 설정 연동:** `~/.config/ghostty/config`를 읽어 테마, 폰트 패밀리, 폰트 크기 등 기존 터미널 취향을 앱에 반영합니다. Ghostty의 macOS Application Support 설정 경로도 함께 확인합니다.
- **Markdown 편집 및 미리보기:** Markdown 원문 편집, GFM 렌더링, 표, 체크리스트, 취소선, 코드 블록 하이라이팅을 지원합니다.
- **작업 경로 파일 확인:** 활성 터미널이나 Markdown 탭의 작업 경로에 맞춰 파일 브라우저를 갱신합니다.
- **변경사항 추적:** Git 저장소의 변경 파일을 사이드바로 보고, 선택한 파일의 줄 단위 Diff를 확인합니다.
- **최근 문서:** 자주 여는 Markdown 문서를 최근 문서 목록에서 다시 열 수 있습니다.
- **macOS 앱 번들:** Dock, 메뉴바, Cmd+Tab, 일반 macOS 윈도우 동작을 지원하는 `.app` 번들로 실행됩니다.

## 터미널 워크플로우

MarkAgent는 터미널을 대체하려는 앱이 아닙니다. Ghostty를 기반으로 터미널 경험을 앱 안에 넣고, 이미 검증된 CLI 도구들과 함께 쓰는 방향에 맞춰져 있습니다.

- 멀티플렉서가 필요하면 `tmux`를 사용합니다.
- 고급 파일 편집은 `vim`, `nvim`, `emacs` 같은 CLI 편집기를 그대로 사용합니다.
- Git, 빌드, 테스트, 패키지 관리, AI 에이전트 실행은 터미널 탭에서 처리합니다.
- Markdown 산출물 확인, 변경사항 검토, 작업 경로 파일 탐색은 MarkAgent의 GUI가 보조합니다.

## AI 에이전트 개발에 맞춘 구성

MarkAgent는 AI 에이전트가 남기는 작업 내역과 결과물을 사람이 검토하기 쉽게 만드는 데 초점을 둡니다.

- 에이전트가 수정한 파일을 Git 변경 목록에서 바로 확인합니다.
- Markdown으로 작성된 계획, 리뷰, 리포트, 작업 로그를 미리보기로 읽습니다.
- 필요한 경우 Raw Edit 모드에서 문서를 직접 수정하고 저장합니다.
- 저장소에는 에이전트를 위한 작업 히스토리와 프로젝트 가이드가 포함될 수 있으며, 이 기록은 포크한 개발자가 맥락을 이해하는 데 도움을 줍니다.

## 빌드와 사용

이 저장소는 자유롭게 포크해서 자신의 개발환경에 맞게 빌드해 사용할 수 있도록 구성되어 있습니다.

요구 사항:

- macOS 14 Sonoma 이상
- Swift 6.0 이상

빌드:

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

`~/Applications`에 앱 번들 설치:

```bash
scripts/bundle.sh install
```

macOS에서 직접 빌드한 앱이 보안 격리(quarantine) 상태로 실행되지 않으면 다음 명령으로 격리 속성을 제거합니다:

```bash
xattr -dr com.apple.quarantine /Applications/MarkAgent.app
```

앱 번들로 Markdown 파일 열기:

```bash
open .build/MarkAgent.app --args README.md
```

## Ghostty 설정

MarkAgent는 다음 순서로 Ghostty 설정 파일을 찾습니다.

1. `~/.config/ghostty/config`
2. `~/Library/Application Support/com.mitchellh.ghostty/config`

현재 구현은 `font-family`, `font-size`, `theme`, `background`, `foreground`, `cursor-color`, `selection-background`, `selection-foreground`, `palette` 값을 읽어 터미널과 앱 테마에 반영합니다.

## 오픈소스

MarkAgent는 다음 오픈소스 라이브러리를 사용합니다.

- `swift-markdown` - Apache-2.0
- `swift-cmark` - BSD-style and MIT notices
- `HighlightSwift` - MIT, 내부 `highlight.js`는 BSD-3-Clause
- `libghostty-spm` - MIT, 포함된 `libghostty`는 자체 라이선스 조건 적용
- `MSDisplayLink` - MIT

## 저장소

https://github.com/dspaudio/markAgent
