# 개발 히스토리

## 목차

1. [세션 1: 프로젝트 기획 문서 정리 및 Phase 1 구현 계획 수립](#세션-1-프로젝트-기획-문서-정리-및-phase-1-구현-계획-수립)
2. [세션 2: Step 1~2 구현 — 프로젝트 스캐폴딩 및 Document 모델](#세션-2-step-12-구현--프로젝트-스캐폴딩-및-document-모델)
3. [세션 3: Step 3 구현 — 기본 마크다운 렌더링](#세션-3-step-3-구현--기본-마크다운-렌더링)
4. [세션 4: Step 4 구현 — GFM 확장 + 코드 하이라이팅](#세션-4-step-4-구현--gfm-확장--코드-하이라이팅)
5. [세션 5: Step 5~7 구현 — FileWatcher, Always-on-Top, 통합 폴리싱](#세션-5-step-57-구현--filewatcher-always-on-top-통합-폴리싱)
6. [세션 6: Phase 2 전체 구현 — Wait 플래그, 양방향 편집, Diff, 템플릿 엔진](#세션-6-phase-2-전체-구현--wait-플래그-양방향-편집-diff-템플릿-엔진)

---

## 전체 타임라인 요약

| 순서 | 내용 | 결과 |
|------|------|------|
| 1 | AGENTS.md 작성 (concept.md 기반, Phase 1 범위) | 프로젝트 개요, 아키텍처, 컨벤션 등 문서화 완료 |
| 2 | Phase 1 세부 구현 계획 수립 | phase1_plan.md — 7 Step 체크리스트 생성 |
| 3 | AGENTS.md에 히스토리 기록 지침 추가 | Workflow Rules 섹션 추가 |
| 4 | 히스토리 기록 형식을 opencode-chat-router 스타일로 변경 | 세션+대화 단위 구분, 목차+타임라인 테이블 |
| 5 | Step 1: 프로젝트 스캐폴딩 | Package.swift, 디렉토리 구조, @main 진입점, swift build 성공 |
| 6 | Step 2: Document 모델 + CLI 인자 처리 | MarkdownDocument, ContentView, 에러 UI, swift build 성공 |
| 7 | 로컬라이제이션 설정 | defaultLocalization: "en" 추가 |
| 8 | 윈도우 미표시 문제 진단 및 해결 | WindowGroup → main.swift + AppDelegate + NSWindow 직접 생성으로 전환 |
| 9 | 윈도우 정상 동작 확인 후 커밋 & 푸시 | dev 브랜치에 반영 완료 |
| 10 | Step 3: 기본 마크다운 렌더링 | MarkdownRenderer (MarkupVisitor) + InlineTextVisitor 구현, ContentView 연동 |
| 11 | Step 4: GFM 확장 + 코드 하이라이팅 | HighlightSwift 통합, GFM 테이블/체크리스트/취소선 렌더링 추가 |
| 12 | Step 5: FileWatcher — 실시간 파일 감시 | DispatchSource 기반 FileWatcher actor 구현, 디바운싱 + 삭제/rename 재오픈, swift build 성공 |
| 13 | Step 6: Always-on-Top 플로팅 윈도우 | window.level = .floating, ⌘⇧T 토글, 메뉴바 항목, 화면 우측 배치, 📌 상태 표시 |
| 14 | Step 7: 통합 폴리싱 — 엣지 케이스 + UI | 빈 파일 구분(isLoaded), LazyVStack 성능 개선, 다크/라이트 모드 확인 |
| 15 | Step 7: 릴리즈 빌드 및 통합 테스트 | swift build -c release 성공 (경고 0), swift test 2/2 통과, 바이너리 2.3MB |
| 16 | Phase 1 완료 — 문서 업데이트 | phase1_plan.md 전체 체크박스 완료, history.md 세션 기록 |
| 17 | Phase 2 설계 및 플랜 수립 | phase2_plan.md 작성 (4 Step, 의존성 그래프, 기술 결정 6건, 파일 영향 매트릭스) |
| 18 | Phase 2 Step 1: Wait 플래그 | CLIArguments 수동 파싱, -w/--wait/--help, applicationShouldTerminateAfterLastWindowClosed |
| 19 | Phase 2 Step 4: 템플릿 엔진 | Template 모델, TemplateEngine ({{var}} 치환), BuiltInTemplates 4종, TemplatePicker Sheet UI |
| 20 | Phase 2 Step 2: 양방향 편집 동기화 | ViewMode, editableContent/isDirty/save(), EditorView, Preview/Edit 전환 (⌘E), 외부 수정 경고 |
| 21 | Phase 2 Step 3: 인라인 Diff 하이라이트 | DiffEngine (CollectionDifference), DiffHighlighter, DiffOverlayView, ⌘D 토글 |
| 22 | Phase 2 완료 — 문서 업데이트 및 릴리즈 빌드 | phase2_plan.md 전체 체크박스 완료, swift build -c release 성공 |

---

## 세션 1: 프로젝트 기획 문서 정리 및 Phase 1 구현 계획 수립

> 날짜: 2026-03-12
> 경로: ~/workspace/markAgent

프로젝트 초기 설정 세션. concept.md를 기반으로 AI 에이전트용 지침서(AGENTS.md)를 작성하고, Phase 1 MVP의 세부 구현 계획을 수립.

### 대화 1: AGENTS.md 작성

**사용자:**
> concept.md의 내용을 읽고 AGENTS.md 파일을 작성해줘. 우선은 phase 1만 반영하면 될 것 같아.

**응답:**
concept.md를 분석하여 Phase 1 MVP 범위의 AGENTS.md를 작성.
포함 내용: Project Overview, Current Scope (Phase 1 핵심 기능 4가지 + 범위 외 항목), Tech Stack, Architecture (3레이어 다이어그램), Planned Directory Structure, Coding Conventions, Key Decisions, Development Commands.

변경 파일: `AGENTS.md` (신규 생성)

---

### 대화 2: Phase 1 구현 계획 수립

**사용자:**
> phase 1을 구현하기 위한 세부 작업 계획을 만들어야 해. phase1_plan.md 파일로 저장하고 진행 내용을 체크할거야. 여러 세션에 걸쳐 진행할 계획이야.

**응답:**
swift-markdown API, SPM macOS 앱 구조, 코드 하이라이팅 라이브러리, Always-on-Top 윈도우 구현 방법 등을 조사한 뒤, 7개 Step으로 분리된 구현 계획을 작성.

- **Step 1:** 프로젝트 스캐폴딩 (Package.swift, 디렉토리, @main 진입점)
- **Step 2:** Document 모델 + CLI 인자 처리
- **Step 3:** 기본 마크다운 렌더링 (MarkupVisitor)
- **Step 4:** GFM 확장 + 코드 하이라이팅
- **Step 5:** FileWatcher (DispatchSource 기반)
- **Step 6:** Always-on-Top 플로팅 윈도우
- **Step 7:** 통합 및 폴리싱

기술 결정 사항: MarkupVisitor 채택 (MarkupWalker 대신), DispatchSource 사용 (단일 파일 감시), NSViewRepresentable으로 NSWindow 접근 (macOS 14 호환).

변경 파일: `phase1_plan.md` (신규 생성)

---

### 대화 3: 히스토리 기록 지침 추가

**사용자:**
> AGENTS.md 파일에 지침으로 커밋 & 푸시 작업을 진행하기 전 이 세션의 진행 내용을 history.md 파일에 기록하도록 해줘.

**응답:**
AGENTS.md에 Workflow Rules 섹션을 추가. 커밋/푸시 전 history.md에 세션 작업 내용을 기록하는 규칙 명시.

변경 파일: `AGENTS.md`

---

### 대화 4: 히스토리 형식 변경

**사용자:**
> 기록의 형식은 ../opencode_chat_router/README.md 파일의 히스토리를 참고해서 수정해줘.

**응답:**
opencode-chat-router README.md의 히스토리 형식을 참고하여 AGENTS.md의 Workflow Rules를 수정. 세션+대화 단위 구분, 사용자/응답 패턴, 목차 + 타임라인 요약 테이블 형식으로 변경.

변경 파일: `AGENTS.md`

---

## 세션 2: Step 1~2 구현 — 프로젝트 스캐폴딩 및 Document 모델

> 날짜: 2026-03-12
> 경로: ~/workspace/markAgent

Phase 1 구현 시작. Step 1(프로젝트 스캐폴딩)과 Step 2(Document 모델 + CLI 인자 처리)를 구현.

### 대화 1: Step 1 + Step 2 구현

**사용자:**
> phase1_plan.md에서 step 1을 먼저 진행하고, 테스트 결과 문제가 없다면 2번까지만 진행해보자. 이후 작업은 다른 세션에서 진행할거야. 2번까지 진행 후 테스트에 문제가 없다면 커밋 & 푸시를 해줘.

**응답:**
SPM macOS SwiftUI 앱 구성, swift-markdown API 등을 조사 후 구현 진행.

**Step 1 (프로젝트 스캐폴딩):**
- `Package.swift` 생성 — executableTarget `ma`, swift-markdown 0.5.0+ 의존성, macOS 14+ 플랫폼
- 디렉토리 구조: `Sources/App/`, `Sources/Core/`, `Sources/Rendering/`, `Sources/Views/`, `Tests/MarkAgentTests/`
- `MarkAgentApp.swift` — `@main` SwiftUI App 진입점 (빈 윈도우)
- `ContentView.swift` — 기본 뷰
- `swift build` 성공 확인 (19초, swift-markdown 0.7.3 + swift-cmark 0.7.1 resolve)

**Step 2 (Document 모델 + CLI 인자 처리):**
- `Document.swift` — `@Observable @MainActor` 마크다운 문서 모델
  - `content`, `fileURL`, `errorMessage` 프로퍼티
  - `load(from:)` — UTF-8 파일 읽기
  - `resolveFileURL(from:)` — 상대/절대 경로 변환 + 파일 존재 검증 (nonisolated static)
  - `DocumentError` enum (Equatable, LocalizedError)
- `MarkAgentApp.swift` — `CommandLine.arguments` 기반 CLI 인자 파싱, Document 연동
- `ContentView.swift` — 3상태 UI (content 표시 / 빈 상태 / 에러 메시지)
- `DocumentTests.swift` — XCTest 기반 유닛 테스트 (경로 resolve 테스트)
- `swift build` 성공

참고: `swift test`는 `xcode-select`가 CommandLineTools를 가리키고 있어 XCTest 모듈을 찾지 못함. Xcode.app은 설치되어 있으나 SDK 전환이 필요.

변경 파일: `Package.swift`, `Sources/App/MarkAgentApp.swift`, `Sources/Core/Document.swift`, `Sources/Views/ContentView.swift`, `Tests/MarkAgentTests/DocumentTests.swift`

---

### 대화 2: 로컬라이제이션 설정

**사용자:**
> 기본 언어는 US English 설정에 추가 언어로 한국어 텍스트를 처리하도록 해야해.

**응답:**
Package.swift에 `defaultLocalization: "en"` 추가. 한국어 텍스트는 UTF-8 기반으로 별도 처리 없이 렌더링됨. 추후 UI 문자열 로컬라이제이션 시 `Resources/ko.lproj/` 추가 가능.

변경 파일: `Package.swift`

---

### 대화 3: macOS 윈도우 미표시 문제 진단

**사용자:**
> `swift run ma README.md` 실행 시 macOS 윈도우가 뜨지 않아. 독의 아이콘을 클릭해야 윈도우가 나타남. Mission Control로 확인해도 윈도우가 생성되지 않고, Cmd+Tab으로 앱 전환해도 윈도우가 안 나옴.

**응답:**
SPM으로 빌드한 executable은 `.app` 번들이 아니므로, SwiftUI `WindowGroup`이 윈도우 생성을 Dock 클릭까지 미루는 문제 확인. `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps:)` 추가를 시도했으나, `@main App.init()` 내에서 `NSApp`에 접근하면 macOS 26에서 assertion failure crash 발생.

1차 시도: `MarkAgentApp.init()`에서 `NSApp.setActivationPolicy(.regular)` → crash
2차 시도: `AppDelegate` + `applicationDidFinishLaunching`에서 activation → 여전히 WindowGroup이 윈도우를 생성하지 않음

변경 파일: `Sources/App/MarkAgentApp.swift`

---

### 대화 4: WindowGroup → AppKit 직접 윈도우 생성으로 전환

**사용자:**
> 아까와 똑같아. Mission Control로 봤을 때 윈도우가 생성되지 않았고, Cmd+Tab으로 앱을 전환해도 윈도우가 생성되지 않고, 독의 아이콘을 클릭해야 윈도우가 나타나.

**응답:**
SwiftUI `WindowGroup`이 SPM executable 환경에서 윈도우를 자동 생성하지 않는 근본적 한계를 확인. 해결책으로 `@main App` + `WindowGroup` 구조를 완전히 버리고, 전통적인 AppKit 방식으로 전환:

- `main.swift` — `NSApplication` 수동 설정 + `NSApp.setActivationPolicy(.regular)` + `NSApp.run()`
- `AppDelegate.swift` — `applicationDidFinishLaunching`에서 `NSWindow` + `NSHostingView<ContentView>` 직접 생성, CLI 인자 파싱 및 Document 로드
- 기존 `MarkAgentApp.swift` 삭제

이 방식으로 `swift run ma README.md` 실행 시 즉시 윈도우가 나타나고 앱이 포그라운드로 활성화됨.

변경 파일: `Sources/App/main.swift` (신규), `Sources/App/AppDelegate.swift` (신규), `Sources/App/MarkAgentApp.swift` (삭제)

---

### 대화 5: 윈도우 정상 동작 확인 및 커밋

**사용자:**
> 원하는 형태가 되었어. 커밋 & 푸시해줘.

**응답:**
윈도우 정상 표시 확인 후 커밋 & 푸시 진행.
- 커밋 메시지: `Replace SwiftUI WindowGroup with AppKit window for reliable launch`
- `dev` 브랜치에서 `origin/dev`로 푸시 완료

변경 파일: `Sources/App/main.swift`, `Sources/App/AppDelegate.swift`, `Sources/App/MarkAgentApp.swift` (삭제)

---

## 세션 3: Step 3 구현 — 기본 마크다운 렌더링

> 날짜: 2026-03-12
> 경로: ~/workspace/markAgent

`swift-markdown`의 `MarkupVisitor`를 사용하여 마크다운 AST → SwiftUI View 트리 변환 구현.

### 대화 1: Step 3 구현

**사용자:**
> 3을 진행해보자.

**응답:**
swift-markdown API와 MarkupVisitor → SwiftUI 변환 패턴을 조사한 뒤 구현 진행.

**설계 결정:**
- 이원 구조 채택: 블록 요소는 `AnyView` 반환 (`MarkdownRenderer`), 인라인 요소는 `SwiftUI.Text` 반환 (`InlineTextVisitor`)
- `ForEach` escaping closure에서 mutating self 캡처 불가 문제 → 헬퍼 메서드를 `static`으로 전환하여 해결
- `Markdown.Text` / `SwiftUI.Text` / `Markdown.Link` / `Markdown.Image` 이름 충돌 → 모듈 prefix로 해결

**구현 내용:**
- `MarkdownRenderer` — `MarkupVisitor<AnyView>` 블록 렌더러
  - Document (VStack 컨테이너), Heading (H1~H6 폰트 차등 + H1/H2 하단 Divider), Paragraph, BlockQuote (좌측 바 + 들여쓰기), OrderedList / UnorderedList / ListItem, CodeBlock (모노스페이스 + 배경), ThematicBreak (Divider), HTMLBlock (fallback)
- `InlineTextVisitor` — `MarkupVisitor<SwiftUI.Text>` 인라인 렌더러
  - Text, Strong (bold), Emphasis (italic), InlineCode (모노스페이스 + 핑크), Link (파란색 + 밑줄), Image (alt text 표시), SoftBreak / LineBreak, InlineHTML (fallback)
- `renderMarkdown(_ source:)` — 공개 API 함수
- `ContentView` 업데이트 — 기존 `Text(document.content)` → `renderMarkdown(document.content)` 연동

**빌드/테스트 결과:** `swift build` 성공, `swift test` 2/2 통과

변경 파일: `Sources/Rendering/MarkdownRenderer.swift` (신규), `Sources/Views/ContentView.swift`, `phase1_plan.md`

---

## 세션 4: Step 4 구현 — GFM 확장 + 코드 하이라이팅

> 날짜: 2026-03-12
> 경로: ~/workspace/markAgent

GFM 확장 요소(테이블, 체크리스트, 취소선) 렌더링 추가 및 HighlightSwift를 활용한 코드 블록 구문 하이라이팅 통합.

### 대화 1: Step 4 구현

**사용자:**
> Step 4까지만 진행해보자.

**응답:**
코드 하이라이팅 라이브러리 비교 조사(Splash/HighlightSwift/Highlightr) 및 swift-markdown GFM 노드 타입 조사를 병렬 수행한 뒤 구현 진행.

**라이브러리 선택:**
- HighlightSwift (appstefan/HighlightSwift) 채택 — highlight.js 기반, 60+ 언어, `AttributedString` 반환, Swift 6 `Sendable` 준수, macOS 13+ 지원, async/await

**GFM 확장 구현:**
- **Strikethrough**: `InlineTextVisitor`에 `visitStrikethrough` 추가 → `.strikethrough()` 수정자
- **체크리스트**: `visitListItem`에서 `listItem.checkbox` 분기 → `.checked`일 때 `checkmark.square.fill`, `.unchecked`일 때 `square` SF Symbol
- **테이블**: `visitTable` + `renderTableRow` / `renderTableCell` static 헬퍼. `Markdown.Table` vs `SwiftUI.Table` 이름 충돌 → 모듈 prefix로 해결. `Table.ColumnAlignment` → `Alignment` / `TextAlignment` 변환 extension 추가

**코드 하이라이팅 구현:**
- `HighlightedCodeBlock` SwiftUI View (CodeHighlighter.swift) — `@State` + `.task`로 비동기 하이라이팅, 언어 자동 감지 또는 명시적 언어 지정, Xcode 테마 기반 라이트/다크 모드 자동 전환
- `MarkdownRenderer.visitCodeBlock`에서 `HighlightedCodeBlock` 사용하도록 연동

**빌드 이슈 해결:**
- `ForEach` escaping closure에서 mutating self 캡처 불가 → static 메서드 전환 (Step 3에서 해결)
- `Markdown.Table` vs `SwiftUI.Table` 이름 충돌 → `Markdown.Table` 모듈 prefix 사용
- `.foregroundColor(.link)` 타입 불일치 → `.foregroundColor(.blue)` 사용
- `.parseMinimalDashes` 옵션 미존재 → 제거
- 빌드 캐시 링크 에러 → `swift package clean` 후 재빌드

**빌드/테스트 결과:** `swift build` 성공, `swift test` 2/2 통과

변경 파일: `Package.swift`, `Sources/Rendering/MarkdownRenderer.swift`, `Sources/Rendering/CodeHighlighter.swift` (신규), `phase1_plan.md`, `.gitignore`

---

## 세션 5: Step 5~7 구현 — FileWatcher, Always-on-Top, 통합 폴리싱

> 날짜: 2026-04-07
> 경로: ~/workspace/markAgent

Phase 1 마무리 세션. Step 5(FileWatcher), Step 6(Always-on-Top), Step 7(통합 폴리싱)을 멀티에이전트 병렬 작업으로 완료.

### 대화 1: Step 5 + Step 6 병렬 구현

**사용자:**
> 5, 6을 진행해야해. 각 에이전트에게 필요한 역할을 할당하고 동시에 진행할 수 있는 것은 동시에 진행해도 돼.

**응답:**
Step 5(FileWatcher)와 Step 6(Always-on-Top)을 독립 에이전트 2개로 병렬 구현. Step 5는 메인 워크트리, Step 6은 격리 워크트리에서 작업 후 수동 통합.

**Step 5 (FileWatcher):**
- `Sources/Core/FileWatcher.swift` 신규 생성 — `actor FileWatcher`로 Swift 6 strict concurrency 준수
- `DispatchSource.makeFileSystemObjectSource` + `O_EVTONLY` 플래그
- `.write`/`.extend` → 0.2초 디바운싱 후 `onChange` 콜백
- `.delete`/`.rename` → 소스 취소 + 지연 재오픈 (에디터 atomic save 대응)
- `@MainActor @Sendable` 콜백으로 Document.load() 직접 호출
- AppDelegate에서 파일 로드 성공 시 `startWatching(url:)` 호출

**Step 6 (Always-on-Top):**
- `window.level = .floating` + `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- `⌘⇧T` 키보드 단축키 토글 + 메뉴바 "Window > Always on Top" 항목
- 타이틀바에 📌 아이콘으로 상태 표시
- `positionWindowOnRight()` — 화면 우측 20pt 여백 기본 배치
- `setupWindow()` / `setupMenu()` 메서드 분리

두 에이전트 완료 후 AppDelegate.swift를 수동 통합하여 FileWatcher + Always-on-Top 모두 반영.

**빌드 결과:** `swift build` 성공

변경 파일: `Sources/Core/FileWatcher.swift` (신규), `Sources/App/AppDelegate.swift`

---

### 대화 2: Step 7 멀티에이전트 팀 구성 및 폴리싱

**사용자:**
> 다음 스텝을 진행하자. 멀티에이전트면 tmux 환경에서 각각 pane이 열려서 상황을 확인할 수 있다고 들었는데, 그 부분도 활용해봐

**응답:**
`step7-polish` 팀을 구성하여 tmux pane 기반 멀티에이전트로 Step 7을 진행.

**팀 구성:**
- `polisher` — Task #1: 엣지 케이스 처리 및 UI 폴리싱
- `tester` — Task #2: 릴리즈 빌드 및 통합 테스트

**polisher 작업 결과:**
- `Document.swift`에 `isLoaded: Bool` 추가 — 빈 파일과 로딩 중 상태 구분
- `ContentView.swift` — 빈 문서(`isLoaded && content.isEmpty`) 시 "빈 문서입니다." 표시
- `MarkdownRenderer.swift` — `visitDocument`에서 `VStack` → `LazyVStack` (대용량 파일 성능)
- 다크/라이트 모드: semantic 색상 전부 시스템 대응 확인 → 수정 불필요
- 윈도우 리사이즈: 기존 구조 정상 → 수정 불필요

**tester 작업 결과:**
- `swift build -c release` 성공 — 경고 0개, clean build
- 릴리즈 바이너리: `.build/release/ma` (2.3MB)
- `swift test` 2/2 통과
- 소스 수정 없이 완료 (기존 코드 clean 상태)

**문서 업데이트:**
- `phase1_plan.md` Step 5, 6, 7 전체 체크박스 완료
- `history.md` 세션 5 기록 및 목차/타임라인 업데이트

변경 파일: `Sources/Core/Document.swift`, `Sources/Views/ContentView.swift`, `Sources/Rendering/MarkdownRenderer.swift`, `phase1_plan.md`, `history.md`

---

## 세션 6: Phase 2 전체 구현 — Wait 플래그, 양방향 편집, Diff, 템플릿 엔진

> 날짜: 2026-04-07
> 경로: ~/workspace/markAgent

Phase 2 Core Interaction 전체 구현 세션. 멀티에이전트 tmux 팀으로 4개 Step을 진행. Step 1+4 병렬 → Step 2 → Step 3 순서.

### 대화 1: Phase 2 설계 및 플랜 수립

**사용자:**
> 멀티에이전트&tmux pane 확인을 사용해서 phase 2를 진행하되, 설계 & 플랜을 세우고 각 스텝별로 나눈 뒤 구현을 시작해줘.

**응답:**
architect 에이전트로 `phase2_plan.md` 작성. 4개 Step, 의존성 그래프, 기술 결정 6건, 파일 영향 매트릭스 포함.

기술 결정 확정: 수동 CLI 파싱, TextEditor, 탭 전환, CollectionDifference, 경고 다이얼로그, Mustache 문법.

변경 파일: `phase2_plan.md` (신규)

---

### 대화 2: Step 1 + Step 4 병렬 구현

**사용자:**
> (자율 진행)

**응답:**
`phase2` 팀 구성 후 `cli-builder`(Step 1)와 `template-builder`(Step 4)를 병렬 배치.

**Step 1 (cli-builder):**
- `CLIArguments.swift` 신규 — `-w`/`--wait`, `-h`/`--help` 수동 파싱
- `main.swift` 수정 — CLIArguments.parse() 호출, --help 시 exit(0)
- `AppDelegate.swift` 수정 — `init(cliArguments:)`, `applicationShouldTerminateAfterLastWindowClosed`, 타이틀에 `[wait]` 표시

**Step 4 (template-builder):**
- `Sources/Templates/` 디렉토리 신규 — Template.swift, TemplateEngine.swift, BuiltInTemplates.swift
- `TemplatePicker.swift` 신규 — NavigationSplitView Sheet UI, 변수 입력 폼
- ContentView + AppDelegate 최소 수정 (⌘T 단축키, 메뉴 항목)

변경 파일: `Sources/App/CLIArguments.swift` (신규), `Sources/App/main.swift`, `Sources/App/AppDelegate.swift`, `Sources/Templates/Template.swift` (신규), `Sources/Templates/TemplateEngine.swift` (신규), `Sources/Templates/BuiltInTemplates.swift` (신규), `Sources/Views/TemplatePicker.swift` (신규), `Sources/Views/ContentView.swift`

---

### 대화 3: Step 2 구현

**응답:**
Step 1 완료 후 `editor-builder` 에이전트로 Step 2 진행.

**구현 내용:**
- `Document.swift` — ViewMode enum, editableContent, isDirty, save(), loadIfNotRecentlySaved(), 외부 수정 감지/해결
- `EditorView.swift` 신규 — @Bindable + TextEditor, 모노스페이스 폰트
- `ContentView.swift` — Preview/Edit 전환 (⌘E), 외부 수정 경고 alert, editableContent 기준 프리뷰 렌더링
- `AppDelegate.swift` — Save(⌘S), Toggle(⌘E) 메뉴, NSWindowDelegate (윈도우 닫기 확인)

핵심 결정: FileWatcher 일시정지 대신 타임스탬프 기반(1초 윈도우)으로 자기 저장 이벤트 억제.

변경 파일: `Sources/Core/Document.swift`, `Sources/Views/EditorView.swift` (신규), `Sources/Views/ContentView.swift`, `Sources/App/AppDelegate.swift`

---

### 대화 4: Step 3 구현

**응답:**
Step 2 완료 후 `diff-builder` 에이전트로 Step 3 진행.

**구현 내용:**
- `DiffEngine.swift` 신규 — CollectionDifference 기반 줄 단위 diff. DiffLineType(.unchanged/.added/.removed), DiffLine, DiffResult
- `Document.swift` 수정 — previousContent, diffResult, showDiff, clearDiff(). load() 시 이전 content 저장 후 백그라운드 diff 계산
- `DiffHighlighter.swift` 신규 — 추가: 초록 배경 + "+", 삭제: 빨간 배경 + "-" + 취소선, 줄 번호 거터
- `DiffOverlayView.swift` 신규 — ScrollView + LazyVStack, diff 요약 헤더, "Diff 닫기" 버튼
- `ContentView.swift` 수정 — ⌘D 토글 버튼, showDiff 시 DiffOverlayView 표시
- `AppDelegate.swift` 수정 — View 메뉴에 "Toggle Diff" (⌘D) 항목

**검증:** `swift build` 성공, `swift build -c release` 성공 (경고 0)

변경 파일: `Sources/Core/DiffEngine.swift` (신규), `Sources/Core/Document.swift`, `Sources/Rendering/DiffHighlighter.swift` (신규), `Sources/Views/DiffOverlayView.swift` (신규), `Sources/Views/ContentView.swift`, `Sources/App/AppDelegate.swift`
