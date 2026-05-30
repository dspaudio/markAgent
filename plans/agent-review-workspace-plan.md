# MarkAgent 에이전트 검토 워크스페이스 플랜

> 날짜: 2026-05-30
> 범위: CLI 에이전트 작업 검토를 강화하는 기능 후보 분석과 1차 구현 계획

## 방향

MarkAgent의 강점은 터미널, 마크다운, Git diff를 같은 창에서 오가며 에이전트 산출물을 검토하는 흐름이다. 범용 IDE 기능을 넓히기보다 "에이전트가 남긴 설명과 실제 변경이 서로 맞는가"를 빠르게 확인하는 기능을 우선한다.

## 기능 후보별 판단

| 우선순위 | 기능 | 구현 가능성 | 1차 범위 | 리스크 |
|---|---|---|---|---|
| 1 | 에이전트 작업 타임라인 / 세션 로그 뷰 | 중간 | 앱 내부 이벤트 로그 모델부터 시작: 터미널 탭 생성, 열린 문서, diff 포커스 이벤트를 시간순으로 묶음 | Ghostty 명령 히스토리 추출 가능 범위 확인 필요 |
| 2 | 마크다운 ↔ Git diff 양방향 점프 | 높음 | 열린 마크다운 문서가 언급한 변경 파일을 Git 변경 목록과 diff 섹션에 표시하고 클릭 시 기존 diff 포커스 경로 사용 | 문서 파싱이 과도하면 오탐 증가 |
| 3 | 프롬프트 스니펫 → 터미널 직접 주입 | 중간 | 활성 터미널 탭이 있을 때 스니펫 row에 주입 버튼 추가 | 터미널 focus와 sendText 안정성 검증 필요 |
| 4 | diff 코멘트/체크 마킹 | 높음 | 파일 단위 reviewed/problem/local note 상태를 UserDefaults 또는 repo-local store에 저장 | 커밋에 포함되지 않는 로컬 상태 위치 결정 필요 |
| 5 | 코드블록 → 터미널 Run | 중간 | shell 언어 코드블록에 Run 버튼과 확인 대화상자 추가 | 위험 명령 방지와 멀티라인 입력 UX 필요 |

## 1차 구현 상세: 마크다운 ↔ Git diff 연결

### 목표

열린 마크다운 문서와 Git 변경 파일 사이의 연결을 탐지해 Git 변경 목록과 diff 뷰에서 보이게 한다. 사용자는 에이전트가 작성한 `plan.md`, `report.md`에서 실제 수정 파일을 언급했는지 바로 확인하고, 변경 파일 row를 클릭해 diff로 이동할 수 있다. Git diff 탭으로 전환한 뒤에도 열린 문서 기준의 연결 신호가 유지되어야 한다.

### 수용 기준

1. 마크다운 본문에 변경 파일 상대 경로가 있으면 해당 변경 파일이 "문서 언급" 상태가 된다.
2. 코드 스팬, 링크 destination, 일반 문장, `path:line` 형태를 모두 인식한다.
3. 부분 문자열 오탐을 피한다. 예: `Sources/App/main.swift.bak`는 `Sources/App/main.swift` 언급으로 처리하지 않는다.
4. 열린 마크다운 탭이 없거나 내용이 비어 있으면 기존 Git diff UI 동작은 변하지 않는다.

### 변경 단위

1. `Sources/Core/MarkdownGitReferenceIndex.swift`
   - 변경 파일 목록과 마크다운 텍스트를 받아 언급된 파일 id 집합을 반환한다.
   - 파일 경로 경계 처리를 중앙화한다.
2. `Tests/MarkAgentTests/MarkdownGitReferenceIndexTests.swift`
   - 코드 스팬/링크/일반 문장/path:line happy path.
   - 빈 문서와 빈 변경 파일 edge case.
   - 유사 접두어/백업 파일명 오탐 방지 regression.
3. `Sources/Views/Main/MainContainerView.swift`
   - 열린 마크다운 문서 내용을 우측 사이드바와 Git diff 탭에 전달한다.
4. `Sources/Views/Sidebar/GitChangesSidebar.swift`
   - 문서 언급 badge 표시.
5. `Sources/Views/Tabs/GitDiffTabView.swift`
   - diff 파일 섹션 헤더에 문서 언급 badge 표시.

## 1차 구현 상세: 에이전트 작업 타임라인

### 목표

우측 작업 사이드바에 Timeline 탭을 추가하고, 에이전트 검토 흐름에서 의미 있는 앱 내부 이벤트를 최신순으로 보여준다. 1차 범위는 터미널 탭 생성, 마크다운 문서 열기, Git diff 파일 포커스다.

### 수용 기준

1. 이벤트는 최신순으로 쌓이고 최대 개수를 넘으면 오래된 이벤트부터 제거된다.
2. 터미널 탭 생성 이벤트는 작업 디렉토리를 detail로 기록한다.
3. 마크다운 문서 열기 이벤트는 파일명을 detail로 기록한다.
4. Git diff 파일 선택 이벤트는 변경 파일 상대 경로를 detail로 기록한다.
5. 이벤트가 없으면 Timeline 탭은 빈 상태 메시지를 보여준다.

### 변경 단위

1. `Sources/Core/AgentTimelineStore.swift`
   - 이벤트 kind, event, action, store를 정의한다.
   - 이벤트 생성 시각과 최대 보관 개수를 테스트 가능하게 주입한다.
2. `Tests/MarkAgentTests/AgentTimelineStoreTests.swift`
   - 최신순 정렬, Git diff focus, limit 동작을 검증한다.
3. `Sources/Views/Sidebar/AgentTimelineSidebarView.swift`
   - Timeline 탭의 빈 상태와 이벤트 row를 렌더링한다.
4. `Sources/Views/Sidebar/RightSidebarView.swift`
   - `타임라인` segmented tab을 추가한다.
5. `Sources/Views/Main/MainContainerView.swift`
   - 터미널 생성, 마크다운 열기, diff 파일 선택 이벤트를 기록한다.

## 다음 단계

1. 타임라인을 Ghostty 명령 히스토리와 연결하려면 터미널 입력/OSC 이벤트에서 명령 단위 추출 가능성을 먼저 확인한다.
2. Git refresh 시점의 changed file snapshot 이벤트를 추가하면 “그때 바뀐 파일” 묶음에 가까워진다.
3. 스니펫 주입은 `TerminalTabState.sendText(_:)` 같은 테스트 가능한 래퍼를 만든 뒤 사이드바에서 활성 터미널로 주입한다.
4. diff 리뷰 마킹은 파일 id 기준 로컬 store를 만들고 Git 변경 row와 diff section header에 체크/문제 상태를 표시한다.
5. 코드블록 Run은 렌더러에 action closure를 주입하는 구조 변경이 필요하므로 Markdown renderer refactor와 함께 진행한다.

## 2차 구현 상세: `.agents` 기반 Timeline persistence와 AI 요약

### 목표

Timeline을 앱 메모리 안에만 두지 않고 저장소 루트의 `.agents/` 폴더에 공유 가능한 작업 요약으로 저장한다. `.agents/timeline.jsonl`은 AI CLI 도구가 append/read 하기 쉬운 source of truth로 사용하고, `.agents/timeline.md`는 사람과 AI가 빠르게 읽는 요약 문서로 유지한다. 커밋 hash는 같은 커밋에 자기 자신을 포함할 수 없으므로 자동 `commit_created` 기록은 하지 않고, 커밋 전에 공유 가능한 `change_summary`를 기록하는 방향으로 둔다.

### 파일 형식 판단

1. `.agents/timeline.jsonl`
   - 각 줄을 독립 이벤트 JSON으로 기록한다.
   - 이벤트 단위 append가 가능해 AI CLI 연계와 충돌 복구에 유리하다.
   - 깨진 줄이 있어도 나머지 이벤트를 읽을 수 있다.
2. `.agents/timeline.md`
   - JSONL의 최근 이벤트를 규칙 기반으로 요약한다.
   - AI가 작업 재개 시 긴 JSONL 전체를 읽지 않고도 최근 맥락을 파악할 수 있게 한다.
   - source of truth는 아니며 언제든 재생성 가능해야 한다.

### 수용 기준

1. Git 저장소 루트가 확인되면 `.agents/timeline.jsonl`과 `.agents/timeline.md`를 생성/갱신한다.
2. Timeline 이벤트 기록 시 JSONL에 한 줄 이벤트를 append하고, MD 요약을 재생성한다.
3. 앱 재시작 또는 store 재생성 후에도 JSONL에서 기존 이벤트를 읽어 최신순으로 표시할 수 있다.
4. `terminal_created`, `markdown_opened`, `git_diff_focused` 같은 런타임 UI 이벤트는 앱 내부 Timeline에만 표시하고 공유 파일에는 기록하지 않는다.
5. 공유 파일에는 커밋 전에 포함 가능한 `change_summary` 이벤트와 변경 파일, insertions, deletions 요약을 기록한다.
6. `.agents` 파일이 없거나 일부 JSONL 줄이 깨져도 UI는 실패하지 않고 읽을 수 있는 이벤트만 사용한다.

### 변경 단위

1. `Sources/Core/AgentTimelineStore.swift`
   - 이벤트를 Codable 구조로 확장한다.
   - `.agents/timeline.jsonl` append/read와 `.agents/timeline.md` 생성 로직을 추가한다.
   - `change_summary` 이벤트와 변경 파일 요약 기록을 지원한다.
2. `Sources/Views/Main/MainContainerView.swift`
   - Git 저장소 루트 변경 및 refresh 완료 시 Timeline store를 저장소 루트와 동기화한다.
   - Git refresh 자체가 공유 Timeline 파일을 dirty로 만들지 않도록 유지한다.
3. `Sources/Views/Sidebar/AgentTimelineSidebarView.swift`
   - 작업 요약 이벤트 icon/tint 표시를 추가한다.
4. `Tests/MarkAgentTests/AgentTimelineStoreTests.swift`
   - JSONL append/read, Markdown summary 생성, 런타임 이벤트 비영속화 테스트를 추가한다.

### 보류/후속

1. `.agents/timeline.jsonl`과 `.agents/timeline.md`의 git tracking 여부는 프로젝트 정책으로 남긴다. 기본 구현은 파일을 생성하되 `.gitignore`를 자동 수정하지 않는다.
2. 전체 diff 본문은 저장하지 않고 변경 파일별 insertions/deletions 요약만 저장한다.
3. 향후 AI CLI가 `agent_note`, `review_decision` 이벤트를 직접 append할 수 있도록 schema 문서를 추가할 수 있다.
