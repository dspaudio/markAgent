# AGENTS.md — MarkAgent

## Project Overview

**MarkAgent**는 CLI 기반 AI 에이전트(Claude Code, Gemini CLI 등)와 연동되는 macOS 네이티브 마크다운 뷰어다.
터미널 워크플로우에서 마크다운 파일을 실시간으로 미려하게 렌더링하는 **비주얼 브릿지** 역할을 한다.

- **슬로건:** "The Professional GUI for your CLI AI Agents."
- **플랫폼:** macOS (네이티브)
- **현재 단계:** Phase 1 — MVP (초경량 뷰어)

---

## Current Scope (Phase 1: MVP)

Phase 1은 읽기 전용 마크다운 뷰어다. 편집 기능 없음.

### 핵심 기능

1. **CLI 실행:** `ma <file>` 명령어로 앱 실행 및 파일 로드
2. **실시간 파일 감시:** `FSEvents` 기반 파일 변경 감지 → 자동 새로고침
3. **GFM 렌더링:** GitHub Flavored Markdown 파싱 + 코드 블록 구문 하이라이팅
4. **플로팅 윈도우:** Always-on-Top 모드로 터미널 옆에 상시 표시

### 범위 외 (Phase 2+)

- `EDITOR` 환경변수 대응 (`ma -w` wait 플래그)
- 양방향 편집 동기화
- Diff 뷰어
- 프롬프트 템플릿 엔진
- Mermaid/KaTeX 렌더링
- 테마 시스템
- Mac App Store 배포

---

## Tech Stack

| 항목 | 선택 | 비고 |
|------|------|------|
| Language | Swift 6.0+ | Strict concurrency |
| UI Framework | SwiftUI | macOS 14+ 타겟 |
| Markdown Parser | `apple/swift-markdown` | GFM 지원 |
| File Watching | FSEvents (DispatchSource / FileSystemWatcher) | 네이티브 API |
| Build System | Xcode / Swift Package Manager | — |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│                  MarkAgent                   │
├──────────┬──────────────┬───────────────────┤
│  CLI     │   Core       │   Rendering       │
│  Layer   │   Layer      │   Layer           │
├──────────┼──────────────┼───────────────────┤
│ Argument │ FileWatcher  │ MarkdownRenderer  │
│ Parser   │ (FSEvents)   │ (swift-markdown)  │
│          │              │                   │
│ App      │ Document     │ CodeHighlighter   │
│ Launcher │ Model        │                   │
│          │              │ ContentView       │
└──────────┴──────────────┴───────────────────┘
```

### CLI Layer
- 명령줄 인자 파싱 (`ma <filepath>`)
- 파일 경로 유효성 검증 후 앱 윈도우 실행

### Core Layer
- **FileWatcher:** FSEvents로 대상 파일 변경 감지, 변경 시 Document 모델 갱신
- **Document Model:** 마크다운 원문 텍스트를 보유하는 ObservableObject

### Rendering Layer
- **MarkdownRenderer:** `swift-markdown`으로 AST 파싱 → SwiftUI View 트리 변환
- **CodeHighlighter:** 코드 블록 언어별 구문 하이라이팅
- **ContentView:** 메인 윈도우 — 스크롤 가능한 마크다운 렌더링 뷰, Always-on-Top 지원

---

## Planned Directory Structure

```
markAgent/
├── AGENTS.md
├── concept.md
├── Package.swift              # SPM 의존성 (swift-markdown 등)
├── Sources/
│   ├── App/
│   │   ├── MarkAgentApp.swift # @main, 윈도우 설정, Always-on-Top
│   │   └── AppDelegate.swift  # CLI 인자 처리, NSApp 설정
│   ├── Core/
│   │   ├── FileWatcher.swift  # FSEvents 기반 파일 감시
│   │   └── Document.swift     # 마크다운 문서 모델 (ObservableObject)
│   ├── Rendering/
│   │   ├── MarkdownRenderer.swift  # swift-markdown AST → SwiftUI 변환
│   │   └── CodeHighlighter.swift   # 코드 블록 구문 하이라이팅
│   └── Views/
│       └── ContentView.swift  # 메인 렌더링 뷰
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
- 파일명 = 타입명 (e.g., `FileWatcher.swift` → `struct FileWatcher`)
- 프로토콜은 `-able`, `-ing` 접미사 지양 — 역할 기반 명명 (e.g., `FileMonitor`)

### Error Handling
- `Result` 타입 또는 `throws` — 강제 언래핑(`!`) 금지
- 파일 I/O 오류는 사용자에게 윈도우 내 인라인 메시지로 표시

---

## Key Decisions

1. **SPM vs Xcode 프로젝트:** SPM 기반으로 시작. Xcode 프로젝트 파일 최소화.
2. **macOS 최소 버전:** macOS 14 (Sonoma) — Observation framework, 최신 SwiftUI API 활용.
3. **CLI 바이너리:** Phase 1에서는 `swift run` 또는 빌드된 바이너리 직접 실행. Homebrew 배포는 Phase 3.
4. **렌더링 전략:** `swift-markdown`의 `MarkupWalker`로 AST를 순회하며 SwiftUI View를 직접 생성. WebView 사용하지 않음.

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

# 실행
swift run ma <filepath>

# 테스트
swift test

# 릴리즈 빌드
swift build -c release
```
