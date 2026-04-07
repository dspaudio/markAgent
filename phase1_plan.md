# Phase 1: MVP 구현 계획

> 여러 세션에 걸쳐 진행. 각 Step은 독립 세션에서 완료 가능한 단위로 설계.
> 체크박스로 진행 상황 추적.

---

## Step 1: 프로젝트 스캐폴딩

빈 SwiftUI 앱이 `swift build` → `swift run ma`로 윈도우가 뜨는 것까지 확인.

- [x] `Package.swift` 생성
  - executableTarget `ma` 정의
  - `apple/swift-markdown` 의존성 추가
  - macOS 14+ 플랫폼 지정
- [x] 디렉토리 구조 생성 (AGENTS.md의 Planned Directory Structure 기준)
  - `Sources/App/`, `Sources/Core/`, `Sources/Rendering/`, `Sources/Views/`
- [x] `MarkAgentApp.swift` — `@main` 진입점 (빈 윈도우)
- [x] `swift build` 성공 확인
- [x] `swift run ma` 실행 시 빈 윈도우 표시 확인

**완료 기준:** `swift run ma`로 빈 macOS 윈도우가 표시된다.

---

## Step 2: Document 모델 + CLI 인자 처리

파일 경로를 인자로 받아 마크다운 텍스트를 읽어오는 코어 로직.

- [x] `Document.swift` — `@Observable` 마크다운 문서 모델
  - `content: String` (마크다운 원문)
  - `fileURL: URL?`
  - `errorMessage: String?` (에러 상태)
  - `func load(from url: URL) throws` — 파일 읽기
- [x] `MarkAgentApp.swift`에서 CLI 인자 파싱
  - `CommandLine.arguments[1]`로 파일 경로 추출
  - 상대 경로 → 절대 경로 변환
  - 파일 존재 여부 검증
  - 인자 없을 시 사용법 안내 또는 빈 상태 표시
- [x] `ContentView.swift` — Document의 `content`를 `Text`로 임시 표시 (렌더링 전 단계)
- [x] 에러 UI — 파일 없음, 읽기 실패 시 인라인 에러 메시지 표시

**완료 기준:** `swift run ma README.md` 실행 시 파일 원문 텍스트가 윈도우에 표시된다.

---

## Step 3: 기본 마크다운 렌더링

`swift-markdown`의 `MarkupVisitor`로 AST를 순회하며 SwiftUI View 트리 생성.
이 단계에서는 핵심 블록/인라인 요소만 구현.

- [x] `MarkdownRenderer.swift` — `MarkupVisitor` 프로토콜 구현
  - `typealias Result` 결정 (`AnyView` 또는 `Text` 분리 전략)
- [x] 블록 요소 렌더링
  - [x] `Heading` (H1~H6, 폰트 크기 차등)
  - [x] `Paragraph`
  - [x] `BlockQuote` (들여쓰기 + 좌측 바)
  - [x] `ListItem` / `OrderedList` / `UnorderedList`
  - [x] `ThematicBreak` (수평선 `---`)
  - [x] `CodeBlock` (모노스페이스, 배경색 — 하이라이팅은 Step 4)
- [x] 인라인 요소 렌더링
  - [x] `Text` (일반 텍스트)
  - [x] `Strong` (볼드)
  - [x] `Emphasis` (이탤릭)
  - [x] `InlineCode` (모노스페이스 배경)
  - [x] `Link` (클릭 가능한 하이퍼링크)
  - [x] `Image` (AsyncImage로 원격 이미지 / 로컬 이미지 로드)
- [x] `ContentView.swift` — `MarkdownRenderer`로 렌더링된 뷰를 `ScrollView`에 표시
- [x] 기본 타이포그래피 설정 (시스템 폰트 기반, 적절한 패딩/간격)

**완료 기준:** 일반적인 마크다운 문서가 서식이 적용되어 읽기 좋게 표시된다. (코드 하이라이팅, GFM 확장은 아직 없음)

---

## Step 4: GFM 확장 + 코드 하이라이팅

GitHub Flavored Markdown 확장 요소 렌더링 및 코드 블록 구문 하이라이팅.

- [x] 코드 하이라이팅 라이브러리 통합
  - `Package.swift`에 하이라이팅 의존성 추가 (후보: Splash, HighlightSwift, Highlightr)
  - `CodeHighlighter.swift` — 언어 식별자 기반 구문 하이라이팅
  - `CodeBlock` 렌더링에 하이라이터 적용
  - 코드 블록 복사 버튼 (선택사항)
- [x] GFM 테이블 렌더링
  - `Table`, `TableHead`, `TableBody`, `TableRow`, `TableCell` 처리
  - 정렬(좌/중/우) 지원
- [x] GFM 체크리스트 (읽기 전용)
  - `ListItem` 내 체크박스 상태 표시
- [x] GFM Strikethrough (취소선)
  - `Strikethrough` → `.strikethrough()` 수정자 적용

**완료 기준:** GFM 문법(테이블, 체크리스트, 취소선)이 올바르게 렌더링되고, 코드 블록에 구문 하이라이팅이 적용된다.

---

## Step 5: FileWatcher (실시간 파일 감시)

파일 변경 감지 → Document 자동 갱신 → 뷰 재렌더링 파이프라인.

- [x] `FileWatcher.swift` — `DispatchSource.makeFileSystemObjectSource` 기반
  - `O_EVTONLY` 플래그로 파일 디스크립터 열기
  - `.write` 이벤트 감시 → `Document.load()` 재호출
  - `.delete` / `.rename` 이벤트 처리 (파일 디스크립터 재오픈)
  - `deinit`에서 리소스 정리 (source cancel, fd close)
- [x] Document 모델과 연동
  - `@Observable`의 `content` 갱신 시 뷰 자동 리렌더링 확인
  - 파일 감시 시작/중지 라이프사이클 관리
- [x] 엣지 케이스 처리
  - 파일이 삭제된 경우 — 에러 메시지 표시 + 감시 재시도 로직
  - 빠른 연속 수정 — 디바운싱 (0.1~0.3초)
  - 대용량 파일 성능 확인

**완료 기준:** 외부에서 파일을 수정하면(예: `echo "# test" >> file.md`) 윈도우가 자동으로 갱신된다.

---

## Step 6: Always-on-Top 플로팅 윈도우

터미널 옆에 상시 표시되는 플로팅 모드.

- [x] `NSViewRepresentable` 기반 `WindowAccessor` 구현
  - `NSWindow` 접근 → `window.level = .floating`
  - `window.collectionBehavior` 설정 (모든 Space에서 표시)
- [x] Always-on-Top 토글 기능
  - 메뉴바 항목 또는 키보드 단축키 (예: `⌘⇧T`)
  - 현재 상태를 타이틀바 또는 UI에 표시
- [x] 윈도우 기본 설정
  - 적절한 기본 크기 (예: 500x700)
  - 화면 우측에 기본 위치
  - 타이틀바에 파일명 표시

**완료 기준:** 앱 실행 시 윈도우가 다른 앱 위에 떠 있고, 토글로 on/off 가능하다.

---

## Step 7: 통합 및 폴리싱

전체 기능 연결 + 엣지 케이스 + UI 다듬기.

- [x] 전체 흐름 통합 테스트
  - `swift run ma <file>` → 파일 로드 → 렌더링 → 파일 수정 → 자동 갱신
  - 존재하지 않는 파일 경로 → 에러 메시지
  - 인자 없이 실행 → 사용법 안내
- [x] 엣지 케이스
  - 빈 파일
  - 매우 큰 파일 (1MB+) — 렌더링 성능
  - 깨진/불완전한 마크다운
  - UTF-8 이외 인코딩
- [x] UI 폴리싱
  - 스크롤 위치 유지 (파일 갱신 시)
  - 적절한 여백, 줄 간격
  - 다크 모드 / 라이트 모드 자동 대응
  - 윈도우 리사이즈 대응
- [x] 빌드 및 배포 준비
  - `swift build -c release` 성공 확인
  - 빌드된 바이너리 직접 실행 확인 (`ma <file>`)
  - 간단한 설치 안내 (README 또는 AGENTS.md 업데이트)

**완료 기준:** 릴리즈 빌드된 `ma` 바이너리가 안정적으로 동작하며, Phase 1 기능이 모두 작동한다.

---

## 의존성 그래프

```
Step 1 (스캐폴딩)
  └─→ Step 2 (Document + CLI)
        └─→ Step 3 (기본 렌더링)
        │     └─→ Step 4 (GFM + 하이라이팅)
        └─→ Step 5 (FileWatcher)
              └─→ Step 6 (Always-on-Top)
                    └─→ Step 7 (통합/폴리싱)
```

Step 3과 Step 5는 Step 2 이후 병렬 진행 가능.

---

## 기술 결정 사항 (조사 결과 기반)

| 항목 | 결정 | 근거 |
|------|------|------|
| AST 순회 패턴 | `MarkupVisitor` | 제네릭 `Result` 타입으로 SwiftUI View 반환 가능. `MarkupWalker`는 `Void` 반환이라 부적합 |
| 파일 감시 | `DispatchSource` | 단일 파일 감시에 충분. FSEvents는 디렉토리 감시에 적합 |
| 코드 하이라이팅 | 구현 시 결정 | 후보: Splash (가볍고 빠름), HighlightSwift (SwiftUI 네이티브), Highlightr (다언어) |
| Always-on-Top | `NSViewRepresentable` → `NSWindow.level` | macOS 14 호환. macOS 15의 `.windowLevel` 수정자는 미사용 |
| 참고 프로젝트 | `gonzalezreal/swift-markdown-ui` | swift-markdown → SwiftUI 변환의 성숙한 구현체 |
