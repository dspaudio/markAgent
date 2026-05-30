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
