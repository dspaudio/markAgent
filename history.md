# 개발 히스토리

## 목차

1. [세션 1: 프로젝트 기획 문서 정리 및 Phase 1 구현 계획 수립](#세션-1-프로젝트-기획-문서-정리-및-phase-1-구현-계획-수립)
2. [세션 2: Step 1~2 구현 — 프로젝트 스캐폴딩 및 Document 모델](#세션-2-step-12-구현--프로젝트-스캐폴딩-및-document-모델)

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
