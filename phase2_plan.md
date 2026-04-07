# Phase 2: Core Interaction 구현 계획

> Phase 1(읽기 전용 뷰어)이 완료된 상태에서, 양방향 연동 기능을 추가한다.
> 각 Step은 독립 세션에서 완료 가능한 단위로 설계하되, Step 간 의존성을 명시한다.
> 체크박스로 진행 상황 추적.

---

## 의존성 그래프

```
Step 1 (Wait 플래그)
  │
  └──→ Step 2 (양방향 편집)  ←── Step 4 (템플릿 엔진) [병렬 가능]
         │
         └──→ Step 3 (Diff 하이라이트)
```

- Step 1 → Step 2: CLI 인자 파싱 인프라 공유. -w 모드에서 편집 후 닫기 = EDITOR 프로토콜 완성.
- Step 2 → Step 3: 편집 모드가 있어야 Diff가 더 유용 (외부 변경 vs 내 편집 비교).
- Step 4: 완전 독립. 신규 파일 위주라 어느 시점에든 병렬 진행 가능.
- Step 1 + Step 4는 병렬 진행 가능 (파일 충돌: AppDelegate.swift의 메뉴 코드만 주의).

---

## 파일 영향 범위 매트릭스

| 파일 | Step 1 | Step 2 | Step 3 | Step 4 |
|------|--------|--------|--------|--------|
| `Sources/App/main.swift` | **수정** | - | - | - |
| `Sources/App/AppDelegate.swift` | **수정** | **수정** | - | 수정 |
| `Sources/App/CLIArguments.swift` | **신규** | - | - | - |
| `Sources/Core/Document.swift` | - | **수정** | **수정** | - |
| `Sources/Core/FileWatcher.swift` | - | **수정** | 수정 | - |
| `Sources/Core/DiffEngine.swift` | - | - | **신규** | - |
| `Sources/Views/ContentView.swift` | - | **수정** | 수정 | 수정 |
| `Sources/Views/EditorView.swift` | - | **신규** | - | - |
| `Sources/Rendering/MarkdownRenderer.swift` | - | - | 수정 | - |
| `Sources/Rendering/DiffHighlighter.swift` | - | - | **신규** | - |
| `Sources/Views/DiffOverlayView.swift` | - | - | **신규** | - |
| `Sources/Templates/Template.swift` | - | - | - | **신규** |
| `Sources/Templates/TemplateEngine.swift` | - | - | - | **신규** |
| `Sources/Templates/BuiltInTemplates.swift` | - | - | - | **신규** |
| `Sources/Views/TemplatePicker.swift` | - | - | - | **신규** |
| `Package.swift` | - | - | 수정 가능 | - |

**볼드**: 해당 Step의 핵심 변경. 일반: 부수적 변경.

---

## 기술 결정 사항

| 항목 | 후보 | 결정 | 근거 |
|------|------|------|------|
| CLI 인자 파싱 | (A) swift-argument-parser (B) 수동 파싱 | **결정 필요** | (A) 타입 안전, 자동 --help 생성, 의존성 1개 추가. (B) 의존성 없음, -w와 파일 경로 2개만이므로 충분. Phase 3에서 플래그가 더 추가되면 (A)로 마이그레이션. |
| 편집 모드 UI | (A) SwiftUI TextEditor (B) NSTextView (AppKit) | **결정 필요** | (A) 간결, SwiftUI 네이티브, 구문 하이라이팅 불가, 대용량 성능 제한. (B) 강력, 줄 번호/구문 하이라이팅 가능, 구현 복잡. 권장: (A)로 시작 — "AI 에이전트용 편집기"로서 raw 텍스트 편집이면 충분. Phase 3에서 (B)로 마이그레이션 가능. |
| Dual Mode 전환 방식 | (A) 탭 전환 (Preview/Edit) (B) 좌우 분할 (Split) (C) 둘 다 | **결정 필요** | (A) 구현 간단, 화면 공간 효율적. (B) 실시간 프리뷰 경험 우수, 화면 폭 필요. 권장: (A) 탭 전환을 기본으로 구현, (B)는 Enhancement로 추가 검토. |
| Diff 알고리즘 | (A) Swift 표준 CollectionDifference (B) 외부 라이브러리 | **결정 필요** | (A) 의존성 없음, 줄 단위 diff 충분, macOS 13+. (B) 단어 단위 diff, 더 정밀한 결과. 권장: (A)로 줄 단위부터 시작. 단어 단위는 Enhancement. |
| 편집 충돌 해결 | (A) Last Write Wins (B) 경고 다이얼로그 (C) 3-way 머지 | **결정 필요** | (A) 간단하지만 데이터 유실 위험. (C) 복잡도 과다. 권장: (B) — 외부 수정 감지 시 "외부 변경 로드 / 내 변경 유지 / 파일로 저장" 3가지 선택지. |
| 템플릿 문법 | (A) Mustache 스타일 `{{var}}` (B) 자체 문법 | **결정 필요** | 권장: (A) — 개발자에게 익숙하고, 간단한 파서로 구현 가능. 조건/루프는 Phase 3+. |

---

## Step 1: Wait 플래그 (`ma -w <file>`)

CLI 레이어를 확장하여 `-w`/`--wait` 플래그를 인식하고, `EDITOR` 환경변수와 호환되는 프로세스 생명주기를 구현한다.

### 현재 상태 분석

현재 `main.swift`는 `app.run()`으로 블로킹되어 앱 종료 시 프로세스도 종료된다.
`AppDelegate.loadFromCLIArguments()`에서 `CommandLine.arguments[1]`만 사용하며, 플래그 파싱 로직이 없다.

### 구현 항목

- [ ] `Sources/App/CLIArguments.swift` — CLI 인자 파싱 구조체 (신규)
  - `CLIArguments` 구조체: `filePath: String?`, `waitMode: Bool`, `showHelp: Bool`
  - `static func parse(_ args: [String]) -> CLIArguments` 메서드
  - `-w`/`--wait` 플래그 인식
  - `--help`/`-h` 플래그 인식
  - 위치 인자(파일 경로)와 플래그 인자 분리
  - 잘못된 인자 조합 시 에러 메시지 (예: 파일 경로 없이 -w만 사용)
- [ ] `Sources/App/main.swift` — 인자 파싱을 CLIArguments로 위임 (수정)
  - `CLIArguments.parse(CommandLine.arguments)` 호출
  - `--help` 시 사용법 출력 후 `exit(0)`
  - 파싱된 결과를 AppDelegate에 전달 (프로퍼티 또는 초기화 인자)
- [ ] `Sources/App/AppDelegate.swift` — wait 모드 적용 (수정)
  - `loadFromCLIArguments()` 리팩토링: CLIArguments 활용
  - wait 모드 시: 윈도우 타이틀에 상태 표시 (예: "file.md — Editing")
  - wait 모드 시: `applicationShouldTerminateAfterLastWindowClosed(_:)` → `true` 반환
  - 앱 종료 시 `exit(0)` 보장 (EDITOR 프로토콜)
- [ ] 사용법 메시지 정의
  - `ma <file>` — 파일 열기 (뷰어 모드)
  - `ma -w <file>` — 파일 열기 (편집 대기 모드, EDITOR 호환)
  - `ma --help` — 사용법 출력
- [ ] `DocumentError` 확장: 인자 관련 에러 케이스 추가

### 완료 기준

- `swift run ma test.md` — 기존 뷰어 동작 유지 (회귀 없음)
- `swift run ma -w test.md` — 앱 실행, 윈도우 닫으면 프로세스 즉시 종료, exit code 0
- `swift run ma --help` — 사용법 출력 후 즉시 종료
- `export EDITOR=".build/debug/ma -w"` 후 에이전트 시뮬레이션 가능

---

## Step 2: 양방향 편집 동기화 (Bi-directional Sync)

읽기 전용 뷰어에 편집 기능을 추가한다. Preview/Edit 듀얼 모드를 구현하고,
앱 내 편집 사항이 원본 파일에 실시간 반영되도록 한다.

### 현재 상태 분석

- `MarkdownDocument`는 `content` (읽기 전용), `load(from:)` 메서드만 보유
- `ContentView`는 `renderMarkdown(document.content)`로 읽기 전용 렌더링
- `FileWatcher`는 외부 변경 감지 → `Document.load()` 재호출 (단방향)
- 저장(save) 기능 없음, 편집 상태 추적 없음

### 구현 항목

#### Phase 2-A: Document 모델 확장

- [ ] `Sources/Core/Document.swift` — 편집 관련 속성/메서드 추가 (수정)
  - `editableContent: String` — 편집 모드에서 사용하는 바인딩용 텍스트
  - `isDirty: Bool` (computed) — `editableContent != content`
  - `lastSavedAt: Date?` — 마지막 저장 시각 (충돌 감지용)
  - `isExternalUpdatePending: Bool` — 외부 수정 감지 플래그
  - `func save() throws` — `editableContent`를 `fileURL`에 UTF-8로 기록
  - `func acceptExternalUpdate()` — 외부 변경 수용 (`content` → `editableContent` 동기화)
  - `func rejectExternalUpdate()` — 외부 변경 거부 (현재 `editableContent` 유지)
  - `load(from:)` 수정: 편집 모드가 아닐 때만 자동 갱신, 편집 중이면 `isExternalUpdatePending = true`

#### Phase 2-B: FileWatcher 자기 수정 무시

- [ ] `Sources/Core/FileWatcher.swift` — self-modification 무시 로직 (수정)
  - `pauseTemporarily()` 메서드: Document.save() 호출 전 감시 일시 중지
  - `resume()` 메서드: save 완료 후 감시 재개
  - 또는 타임스탬프 기반: save 시 타임스탬프 기록 → 직후 이벤트 무시
  - 0.5초 이내 이벤트를 self-modification으로 간주

#### Phase 2-C: EditorView 구현

- [ ] `Sources/Views/EditorView.swift` — 마크다운 텍스트 편집 뷰 (신규)
  - `TextEditor(text: $document.editableContent)` 기반
  - 모노스페이스 폰트 적용 (마크다운 원문 편집에 적합)
  - 줄 번호 표시 (선택적 — SwiftUI TextEditor에서는 제한적, 가능하면 추가)
  - 미저장 변경 표시 (예: 타이틀바에 dot indicator 또는 "Modified" 텍스트)
  - `Command+S` 키보드 단축키 → save() 호출

#### Phase 2-D: Dual Mode ContentView

- [ ] `Sources/Views/ContentView.swift` — Preview/Edit 모드 전환 (수정)
  - `ViewMode` enum: `.preview`, `.edit`
  - `@State private var viewMode: ViewMode = .preview`
  - `.preview`: 현재 `renderMarkdown()` (변경 없음)
  - `.edit`: `EditorView` 표시
  - 모드 전환: 툴바 버튼 또는 `Command+E` 단축키
  - 모드 전환 시 데이터 동기화: edit → preview 전환 시 `editableContent`로 렌더링

#### Phase 2-E: 충돌 감지 및 해결 UI

- [ ] 외부 수정 감지 시 경고 다이얼로그
  - "파일이 외부에서 수정되었습니다."
  - 선택지: "외부 변경 로드" / "내 변경 유지" / "취소"
  - NSAlert 또는 SwiftUI .alert 활용
- [ ] 윈도우 닫기 시 미저장 변경 확인
  - `NSWindowDelegate.windowShouldClose(_:)` 활용
  - isDirty면 "저장 / 저장 안 함 / 취소" 다이얼로그
  - `AppDelegate`에서 `NSWindowDelegate` 구현

#### Phase 2-F: 메뉴 및 단축키

- [ ] `Sources/App/AppDelegate.swift` — Edit 메뉴 확장 (수정)
  - File 메뉴: Save (Command+S)
  - View 메뉴: Toggle Preview/Edit (Command+E)
  - 메뉴 항목 상태 동기화 (현재 모드 표시)

### 완료 기준

- `Command+E`로 Preview/Edit 모드 전환 가능
- Edit 모드에서 텍스트 수정 → `Command+S` → 원본 파일에 변경 반영 확인 (`cat file.md`)
- 외부에서 `echo "new line" >> file.md` 실행 시:
  - Preview 모드: 자동 갱신 (기존 동작 유지)
  - Edit 모드: 외부 수정 경고 다이얼로그 표시
- 앱 자체 저장 시 FileWatcher가 이중 갱신하지 않음
- isDirty 상태에서 윈도우 닫기 시 저장 확인 다이얼로그 표시
- `-w` 모드에서 편집 후 저장하고 윈도우 닫기 = 프로세스 종료 (Step 1 연동)

---

## Step 3: 인라인 Diff 하이라이트

외부(AI 에이전트 등)에서 파일을 수정했을 때, 이전 버전과의 차이를 시각적으로 표시한다.

### 현재 상태 분석

- `FileWatcher`가 파일 변경을 감지하면 `Document.load()` 재호출
- `load()` 시 이전 content를 저장하지 않고 덮어쓰기
- 변경 내역 추적 메커니즘 없음

### 구현 항목

#### Phase 3-A: DiffEngine 구현

- [ ] `Sources/Core/DiffEngine.swift` — Diff 계산 로직 (신규)
  - `DiffLineType` enum: `.unchanged`, `.added`, `.removed`, `.modified`
  - `DiffLine` 구조체: `type: DiffLineType`, `content: String`, `lineNumber: Int?`, `oldLineNumber: Int?`
  - `DiffResult` 구조체: `lines: [DiffLine]`, `addedCount: Int`, `removedCount: Int`
  - `static func compute(old: String, new: String) -> DiffResult`
  - 줄 단위 diff: Swift 표준 `CollectionDifference` 활용
  - 빈 문자열(첫 로드) 시 diff 없음 처리

#### Phase 3-B: Document 모델 확장

- [ ] `Sources/Core/Document.swift` — diff 관련 속성 추가 (수정)
  - `previousContent: String?` — 직전 버전 텍스트
  - `diffResult: DiffResult?` — 계산된 diff
  - `showDiff: Bool = false` — diff 표시 토글
  - `load(from:)` 수정: 새 content 로드 전 현재 content를 previousContent에 저장 → 로드 후 diff 계산
  - diff 계산은 백그라운드 Task로 수행 (대용량 파일 UI 블로킹 방지)
  - `clearDiff()` 메서드: diff 결과 초기화

#### Phase 3-C: Diff 렌더링

- [ ] `Sources/Rendering/DiffHighlighter.swift` — Diff 시각화 (신규)
  - `DiffLine` → SwiftUI View 변환
  - 추가된 줄: `Color.green.opacity(0.15)` 배경 + 좌측 `+` 표시
  - 삭제된 줄: `Color.red.opacity(0.15)` 배경 + 좌측 `-` 표시 + 취소선
  - 변경 없는 줄: 기본 스타일
  - 줄 번호 거터(gutter) 표시
  - 다크 모드/라이트 모드 대응
- [ ] `Sources/Views/DiffOverlayView.swift` — Diff 전용 뷰 (신규)
  - diff가 활성화되었을 때 표시되는 전체 뷰
  - `ScrollView` 안에 diff 줄 목록 표시
  - diff 요약 정보 표시 ("+N줄 추가, -M줄 삭제")
  - "Diff 닫기" 버튼

#### Phase 3-D: ContentView 통합

- [ ] `Sources/Views/ContentView.swift` — Diff 토글 UI (수정)
  - Diff 활성화 시: 기존 마크다운 렌더링 대신 DiffOverlayView 표시
  - 또는: 마크다운 렌더링 위에 Diff 하이라이트 오버레이
  - Diff 토글 버튼 (툴바 또는 `Command+D`)
  - diff가 존재할 때만 토글 버튼 활성화
  - ViewMode에 `.diff` 추가 또는 독립 오버레이로 처리

#### Phase 3-E: FileWatcher 연동 (선택적)

- [ ] `Sources/Core/FileWatcher.swift` — diff 트리거 (수정, 경미)
  - 직접 변경 없을 수 있음 — Document.load()에서 previousContent 저장이 핵심
  - 필요 시: 변경 이벤트 타입(write/delete/rename)에 따라 diff 동작 분기

### Package.swift 변경

- [ ] Diff 라이브러리 추가 여부 결정
  - Swift 표준 `CollectionDifference`로 충분하면 변경 없음
  - 단어 단위 diff가 필요하면 외부 패키지 추가 (예: `Differ`, `DiffSwift`)

### 완료 기준

- 외부에서 파일 수정 시 (`echo "added line" >> file.md`) → Diff 하이라이트 자동 표시 가능
- `Command+D`로 Diff 보기 토글 on/off
- 추가된 줄: 초록 배경, 삭제된 줄: 빨간 배경으로 명확히 구분
- diff 요약 정보 ("+3줄, -1줄") 표시
- diff 계산이 UI를 블로킹하지 않음 (1000줄 파일 기준)
- 첫 로드 시(previousContent 없음) diff가 표시되지 않음

---

## Step 4: AI 프롬프트 템플릿 엔진

AI가 이해하기 좋은 구조의 마크다운 템플릿을 제공하고, 변수를 치환하여 새 문서를 생성한다.

### 현재 상태 분석

- 템플릿 관련 코드 없음
- 신규 기능으로 기존 코드 수정 최소 (메뉴 추가, ContentView에 진입점 추가 정도)

### 구현 항목

#### Phase 4-A: 템플릿 모델

- [ ] `Sources/Templates/Template.swift` — 템플릿 데이터 모델 (신규)
  - `Template` 구조체: `id`, `name`, `description`, `content` (마크다운 원문), `variables`
  - `TemplateVariable` 구조체: `name`, `placeholder`, `defaultValue`, `description`
  - `Codable` 준수 (향후 사용자 정의 템플릿 저장/로드 대비)

#### Phase 4-B: 템플릿 엔진

- [ ] `Sources/Templates/TemplateEngine.swift` — 파싱 및 치환 (신규)
  - `static func render(_ template: Template, variables: [String: String]) -> String`
  - `{{variable}}` 패턴 매칭 → 값 치환
  - 미입력 변수는 placeholder 유지 또는 빈 문자열
  - 정규식 기반 파싱: `\{\{(\w+)\}\}`
  - 에러 처리: 잘못된 템플릿 문법 시 원문 유지

#### Phase 4-C: 내장 템플릿

- [ ] `Sources/Templates/BuiltInTemplates.swift` — 내장 템플릿 정의 (신규)
  - **Task 템플릿**: AI에게 작업을 지시하는 구조
    ```
    # Task: {{task_name}}
    ## Context
    {{context}}
    ## Constraints
    {{constraints}}
    ## Expected Output
    {{expected_output}}
    ```
  - **Bug Report 템플릿**: 버그 보고 구조
    ```
    # Bug: {{title}}
    ## 증상
    {{symptom}}
    ## 재현 단계
    {{steps}}
    ## 예상 동작
    {{expected}}
    ## 실제 동작
    {{actual}}
    ```
  - **Code Review 요청 템플릿**: 코드 리뷰 구조
    ```
    # Code Review: {{file_path}}
    ## 변경 요약
    {{summary}}
    ## 검토 포인트
    {{review_points}}
    ```
  - **Feature Request 템플릿**: 기능 요청 구조
  - 각 템플릿에 변수 목록 및 설명 포함

#### Phase 4-D: 템플릿 선택 UI

- [ ] `Sources/Views/TemplatePicker.swift` — 템플릿 선택/적용 UI (신규)
  - Sheet 또는 Popover로 표시
  - 템플릿 목록 (이름 + 설명)
  - 선택 시 변수 입력 폼 표시
  - "적용" 버튼: 템플릿 렌더링 → 새 Document 또는 현재 editableContent에 삽입
  - "취소" 버튼

#### Phase 4-E: 통합

- [ ] `Sources/Views/ContentView.swift` — 템플릿 진입점 추가 (수정)
  - 툴바에 "템플릿" 버튼 추가
  - `Command+T` 단축키
  - 빈 문서 상태에서 템플릿 제안 표시 (선택적)
- [ ] `Sources/App/AppDelegate.swift` — 메뉴 추가 (수정)
  - Edit 또는 File 메뉴에 "Insert Template..." 항목 추가
  - 단축키: `Command+T`

### 디렉토리 구조

```
Sources/
├── Templates/              ← 신규 디렉토리
│   ├── Template.swift
│   ├── TemplateEngine.swift
│   └── BuiltInTemplates.swift
```

### 완료 기준

- `Command+T`로 템플릿 피커 표시
- 내장 템플릿(4종 이상) 목록에서 선택 가능
- 변수 입력 후 "적용" → 마크다운 문서에 템플릿 내용 삽입
- `{{variable}}` 패턴이 올바르게 치환됨
- 미입력 변수에 대한 placeholder 처리

---

## 위험 요소 및 완화 방안

| 위험 | 영향도 | 발생 가능성 | 완화 방안 |
|------|--------|------------|-----------|
| 양방향 편집 시 동시성 충돌 (앱 편집 + 외부 AI 수정) | 높음 | 높음 | 경고 다이얼로그 3가지 선택지. FileWatcher 일시 정지 메커니즘. |
| TextEditor 대용량 파일 성능 | 중간 | 중간 | Phase 2는 수백 줄 이하 지원 목표. 대용량은 Phase 3 NSTextView로 대응. |
| Diff 계산 UI 블로킹 | 중간 | 낮음 | 백그라운드 Task로 diff 계산, @MainActor에서 결과 적용. |
| Swift 6 strict concurrency 위반 | 중간 | 중간 | Document는 @MainActor 유지. FileWatcher는 actor. save()는 nonisolated async로 파일 I/O 분리. |
| 다중 인스턴스 충돌 (-w 모드로 여러 파일 동시 열기) | 낮음 | 중간 | 각 인스턴스가 독립 프로세스. 동일 파일을 다중 인스턴스에서 열 경우 경고. |
| 템플릿 엔진 범위 크리프 | 낮음 | 중간 | Phase 2는 `{{var}}` 치환만. 조건/루프/include는 Phase 3+로 명시적 제한. |

---

## 검증 계획 (전체 통합)

Phase 2 전체 완료 후 다음 시나리오를 테스트한다.

### 시나리오 1: EDITOR 워크플로우

```bash
export EDITOR=".build/release/ma -w"
# AI 에이전트(또는 수동)가 EDITOR 호출 시뮬레이션:
$EDITOR /tmp/test_prompt.md
# → MarkAgent 앱 실행, 편집 가능 상태
# → 사용자가 텍스트 편집 후 Command+S로 저장
# → 윈도우 닫기 → 프로세스 종료, exit 0
# → 에이전트가 수정된 파일을 읽어 계속 진행
```

### 시나리오 2: AI 에이전트 실시간 협업

```bash
ma document.md &
# → MarkAgent가 document.md를 Preview 모드로 표시
# → AI 에이전트가 document.md를 수정 (echo "# New Section" >> document.md)
# → MarkAgent가 변경 감지, 자동 갱신 + Diff 하이라이트 표시
# → 사용자가 Command+D로 Diff 확인
# → 사용자가 Command+E로 Edit 모드 전환, 추가 수정
# → Command+S로 저장 → 에이전트가 변경 감지
```

### 시나리오 3: 템플릿 기반 프롬프트 작성

```bash
ma -w /tmp/new_prompt.md
# → MarkAgent 앱 실행, 빈 문서
# → Command+T로 템플릿 피커 열기
# → "Task" 템플릿 선택 → 변수 입력 → 적용
# → Edit 모드에서 추가 수정
# → Command+S → 윈도우 닫기 → 프로세스 종료
# → 에이전트가 구조화된 프롬프트 파일을 읽어 작업 수행
```

### 회귀 테스트

- `swift run ma README.md` — Phase 1 읽기 전용 뷰어 동작 완전 유지
- FileWatcher 실시간 갱신 동작 유지
- Always-on-Top 토글 동작 유지
- GFM 렌더링 + 코드 하이라이팅 동작 유지
- `swift build -c release` 빌드 성공 (경고 0)
- `swift test` 기존 테스트 통과

---

## 예상 디렉토리 구조 (Phase 2 완료 후)

```
Sources/
├── App/
│   ├── main.swift              # NSApplication 설정 + CLIArguments 파싱
│   ├── AppDelegate.swift       # 윈도우/메뉴 관리, wait 모드, NSWindowDelegate
│   └── CLIArguments.swift      # CLI 인자 파싱 구조체 (신규)
├── Core/
│   ├── Document.swift          # 편집 + 저장 + diff 상태 추가
│   ├── FileWatcher.swift       # self-modification 무시 로직 추가
│   └── DiffEngine.swift        # 줄 단위 diff 계산 (신규)
├── Rendering/
│   ├── MarkdownRenderer.swift  # 기존 유지
│   ├── CodeHighlighter.swift   # 기존 유지
│   └── DiffHighlighter.swift   # diff 시각화 (신규)
├── Views/
│   ├── ContentView.swift       # Dual Mode + Diff 토글 + 템플릿 진입점
│   ├── EditorView.swift        # TextEditor 기반 편집 뷰 (신규)
│   ├── DiffOverlayView.swift   # diff 전용 뷰 (신규)
│   └── TemplatePicker.swift    # 템플릿 선택 UI (신규)
└── Templates/
    ├── Template.swift          # 템플릿 모델 (신규)
    ├── TemplateEngine.swift    # 파싱/치환 (신규)
    └── BuiltInTemplates.swift  # 내장 템플릿 (신규)
```
