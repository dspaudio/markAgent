# AGENTS.md — MarkAgent

## Project Overview

**MarkAgent**는 CLI 기반 AI 에이전트(Claude Code, Gemini CLI 등)와 연동되는 macOS 네이티브 마크다운 에디터/뷰어다.
터미널 워크플로우에서 마크다운 파일을 실시간으로 렌더링하고 편집하는 **비주얼 브릿지** 역할을 한다.

- **슬로건:** "The Professional GUI for your CLI AI Agents."
- **플랫폼:** macOS (네이티브)
- **현재 단계:** Phase 3 — Polishing & Launch

---

## Completed Phases

### Phase 1: MVP (완료)

1. **CLI 실행:** `ma <file>` 명령어로 앱 실행 및 파일 로드
2. **실시간 파일 감시:** `FSEvents` 기반 파일 변경 감지 → 자동 새로고침
3. **GFM 렌더링:** GitHub Flavored Markdown 파싱 + 코드 블록 구문 하이라이팅
4. **플로팅 윈도우:** Always-on-Top 모드로 터미널 옆에 상시 표시

### Phase 2: Core Interaction (완료)

1. **Wait 플래그:** `ma -w <file>` — 편집 완료 후 프로세스 종료
2. **양방향 편집:** Preview/Edit 모드 전환 (⌘E), 파일 저장 (⌘S), 외부 수정 감지
3. **인라인 Diff:** CollectionDifference 기반 변경사항 하이라이트 (⌘D)
4. **템플릿 엔진:** Mustache 문법 기반 프롬프트 템플릿 (⌘T)

### .app 번들 전환 (완료)

SPM 순수 바이너리는 macOS Dock/Cmd+Tab/메뉴바에 표시되지 않음.
`scripts/bundle.sh`로 `.app` 번들을 생성하고, CLI 실행 시 자동으로 번들 경유 재실행.

---

## Current Scope (Phase 3: Polishing & Launch)

### 예정 기능

- Mermaid(다이어그램) 및 KaTeX(수식) 렌더링
- 개발자 친화적 테마 (Dracula, Nord 등) 및 커스텀 CSS
- LLM 입력 비용 예측을 위한 토큰 카운터
- Pipe Support (`cat file.md | ma`)
- 앱 아이콘
- Mac App Store 배포 ($0.99) + Homebrew CLI 배포

---

## Tech Stack

| 항목 | 선택 | 비고 |
|------|------|------|
| Language | Swift 6.0+ | Strict concurrency |
| UI Framework | SwiftUI | macOS 14+ 타겟 |
| Markdown Parser | `apple/swift-markdown` | GFM 지원 |
| Code Highlighting | `HighlightSwift` | highlight.js 기반, 60+ 언어 |
| File Watching | FSEvents (DispatchSource) | 네이티브 API |
| Build System | Swift Package Manager | `scripts/bundle.sh`로 .app 번들 생성 |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                       MarkAgent                          │
├──────────┬───────────────┬───────────────┬──────────────┤
│  CLI     │   Core        │   Rendering   │  Templates   │
│  Layer   │   Layer       │   Layer       │  Layer       │
├──────────┼───────────────┼───────────────┼──────────────┤
│ main     │ FileWatcher   │ Markdown      │ Template     │
│ (relaunch│ (FSEvents)    │ Renderer      │ Engine       │
│  via .app│               │               │              │
│  bundle) │ Document      │ Code          │ BuiltIn      │
│          │ Model         │ Highlighter   │ Templates    │
│ CLI      │               │               │              │
│ Arguments│ DiffEngine    │ Diff          │ Template     │
│          │               │ Highlighter   │ Picker       │
│ App      │               │               │              │
│ Delegate │               │ ContentView   │              │
│          │               │ EditorView    │              │
│          │               │ DiffOverlay   │              │
└──────────┴───────────────┴───────────────┴──────────────┘
```

### CLI Layer
- `main.swift`: CLI 인자 파싱, .app 번들 외부 실행 시 번들 탐색 → `open` 명령으로 재실행
- `CLIArguments`: `-w`/`--wait`, `-h`/`--help` 플래그 파싱
- `AppDelegate`: NSWindow + NSHostingView 생성, 메뉴 구성, 윈도우 라이프사이클

### Core Layer
- **FileWatcher:** `DispatchSource` + `O_EVTONLY`로 파일 변경 감지, 0.2초 디바운싱, 삭제/rename 재오픈
- **Document Model:** `@Observable @MainActor`, ViewMode (preview/edit), editableContent, isDirty, save/load, 외부 수정 감지
- **DiffEngine:** `CollectionDifference` 기반 줄 단위 diff 계산

### Rendering Layer
- **MarkdownRenderer:** `MarkupVisitor<AnyView>` — AST → SwiftUI View 트리 (GFM 테이블/체크리스트/취소선 포함)
- **CodeHighlighter:** `HighlightSwift` 기반 비동기 구문 하이라이팅, 다크/라이트 모드 자동 전환
- **DiffHighlighter:** 추가/삭제 줄 하이라이트 + 줄 번호 거터
- **ContentView:** Preview/Edit 전환, Diff 오버레이, 에러/빈 문서 상태 표시
- **EditorView:** TextEditor 기반 마크다운 편집기

### Templates Layer
- **TemplateEngine:** `{{variable}}` Mustache 치환
- **BuiltInTemplates:** 프롬프트 템플릿 4종 (Bug Report, Feature Request 등)
- **TemplatePicker:** NavigationSplitView Sheet UI, 변수 입력 폼

---

## Directory Structure

```
markAgent/
├── CLAUDE.md                   # 프로젝트 가이드 (이 파일)
├── concept.md                  # 제품 기획안
├── Package.swift               # SPM 매니페스트
├── scripts/
│   └── bundle.sh               # .app 번들 빌드/설치 스크립트
├── Sources/
│   ├── App/
│   │   ├── main.swift          # 진입점, .app 번들 재실행 로직
│   │   ├── AppDelegate.swift   # NSWindow 생성, 메뉴, 윈도우 델리게이트
│   │   ├── CLIArguments.swift  # CLI 인자 파싱
│   │   └── Info.plist          # .app 번들용 (빌드 시 복사)
│   ├── Core/
│   │   ├── Document.swift      # 마크다운 문서 모델 (@Observable)
│   │   ├── FileWatcher.swift   # FSEvents 기반 파일 감시 (actor)
│   │   └── DiffEngine.swift    # 줄 단위 diff 계산
│   ├── Rendering/
│   │   ├── MarkdownRenderer.swift  # AST → SwiftUI (MarkupVisitor)
│   │   ├── CodeHighlighter.swift   # 코드 블록 구문 하이라이팅
│   │   └── DiffHighlighter.swift   # Diff 줄 하이라이트
│   ├── Templates/
│   │   ├── Template.swift          # 템플릿 모델
│   │   ├── TemplateEngine.swift    # Mustache 치환 엔진
│   │   └── BuiltInTemplates.swift  # 내장 템플릿 4종
│   └── Views/
│       ├── ContentView.swift       # 메인 뷰 (Preview/Edit/Diff)
│       ├── EditorView.swift        # 텍스트 편집 뷰
│       ├── DiffOverlayView.swift   # Diff 오버레이
│       └── TemplatePicker.swift    # 템플릿 선택 Sheet
└── Tests/
    └── MarkAgentTests/
```

---

## Coding Conventions

### Swift Style
- Swift 6.0+ strict concurrency 모드 사용
- `@MainActor`를 UI 관련 코드에 명시
- `async/await` 우선, Combine은 최소화
- 타입 추론에 의존하되, 공개 API는 명시적 타입 선언

### SwiftUI Patterns
- `@Observable` (Observation framework) 사용 — `@ObservableObject` 대신
- View는 작고 단일 책임으로 분리
- Preview 매크로(`#Preview`) 활용

### Naming
- 파일명 = 타입명 (e.g., `FileWatcher.swift` → `actor FileWatcher`)
- 프로토콜은 `-able`, `-ing` 접미사 지양 — 역할 기반 명명

### Error Handling
- `Result` 타입 또는 `throws` — 강제 언래핑(`!`) 금지
- 파일 I/O 오류는 사용자에게 윈도우 내 인라인 메시지로 표시

---

## Key Decisions

1. **SPM + .app 번들:** SPM으로 빌드, `scripts/bundle.sh`로 .app 번들 생성. Dock/메뉴/Cmd+Tab 정상 동작에 필수.
2. **macOS 최소 버전:** macOS 14 (Sonoma) — Observation framework, 최신 SwiftUI API 활용.
3. **AppKit 윈도우 직접 생성:** SwiftUI `WindowGroup`은 SPM executable에서 윈도우를 자동 생성하지 않아, `NSWindow` + `NSHostingView` 방식 채택.
4. **렌더링 전략:** `swift-markdown`의 `MarkupVisitor`로 AST를 순회하며 SwiftUI View를 직접 생성. WebView 미사용.
5. **CLI 자동 재실행:** `main.swift`에서 `.app/Contents/MacOS/` 경로 밖 실행 감지 시 상위 디렉토리에서 `.app` 번들을 찾아 `open` 명령으로 재실행.

---

## Workflow Rules

### 커밋 & 푸시 전 히스토리 기록 (필수)

커밋 또는 푸시를 수행하기 **전에** 반드시 `history.md` 파일에 해당 세션의 작업 내용을 기록해야 한다.

**기록 형식:**

세션 단위로 구분하고, 각 세션 내 주요 대화/작업을 순서대로 기록한다.

```markdown
## 세션 N: 세션 제목 (한 줄 요약)

> 날짜: YYYY-MM-DD
> 경로: ~/workspace/markAgent

세션의 배경과 목적을 1~2문장으로 요약.

### 대화 1: 작업/대화 제목

**사용자:**
> 사용자의 요청 원문 또는 요약

**응답:**
수행한 작업 내용과 결과를 요약. 기술적 결정, 변경 사유를 포함.

변경 파일: `path/to/file.swift`, `path/to/other.swift`

---

### 대화 2: 다음 작업/대화 제목

(동일 패턴 반복)
```

`history.md` 파일의 최상단에는 아래 형태의 **목차**와 **타임라인 요약 테이블**을 유지한다.
새 세션이 추가될 때마다 목차와 테이블도 함께 업데이트한다.

```markdown
# 개발 히스토리

## 목차
1. [세션 1: 제목](#세션-1-제목)
2. [세션 2: 제목](#세션-2-제목)

## 전체 타임라인 요약

| 순서 | 내용 | 결과 |
|------|------|------|
| 1 | 작업 요약 | 결과 요약 |
```

**규칙:**
- `history.md`가 없으면 새로 생성한다.
- 새 세션은 기존 내용 아래에 추가(append)한다. 기존 기록을 수정하지 않는다.
- 목차와 타임라인 요약 테이블은 새 세션 추가 시 함께 업데이트한다.
- 히스토리 기록 자체도 커밋에 포함시킨다.

---

## Development Commands

```bash
# 빌드
swift build

# 번들 생성 (debug)
scripts/bundle.sh

# 번들 생성 (release)
scripts/bundle.sh release

# 설치 (~/Applications + /usr/local/bin/ma)
scripts/bundle.sh install

# 실행 (번들 자동 경유)
.build/debug/ma <filepath>

# 실행 (직접 번들)
open .build/MarkAgent.app --args <filepath>

# 테스트
swift test

# 릴리즈 빌드
swift build -c release
```
