# 🚀 MarkAgent: AI-Native Markdown Bridge Editor

AI 에이전트(Codex CLI, Claude Code, Gemini CLI 등)와 CLI 환경에서 매끄럽게 연동되는 초경량 마크다운 에디터/뷰어 기획안입니다.

---

## 💡 제품 컨셉 (Core Concept)
* **정의:** 단순한 편집기가 아닌, CLI 기반 AI 워크플로우를 위한 **'비주얼 브릿지'**.
* **슬로건:** "The Professional GUI for your CLI AI Agents."
* **배포 전략:** OSS(Open Source Software)로 공개하고, GitHub 릴리스와 Homebrew 기반 설치 경로를 제공한다.

---

## 🛠️ 시스템 아키텍처 (System Architecture)

### 1. CLI 인터페이스 레이어 (The Bridge)
* **`EDITOR` 환경변수 대응:** `export EDITOR="ma -w"` 설정을 통해 에이전트가 편집기를 호출할 때 즉시 팝업.
* **File Watcher:** AI 에이전트가 파일을 수정하면 실시간(Real-time)으로 렌더링 화면 갱신.
* **Pipe Support:** 터미널 명령 결과를 파이프(`|`)로 받아 즉시 시각화.

### 2. 코어 에디팅 레이어 (The Editor)
* **Native Performance:** Swift/SwiftUI 기반의 네이티브 앱으로 0.1초 내 실행 속도 확보.
* **Dual Mode:** 렌더링 결과를 보는 **Preview 모드**와 원본 마크다운을 직접 수정하는 **Raw Edit 모드**의 조화.

### 3. AI 컨텍스트 레이어 (Context Manager)
* **Diff Viewer:** AI의 수정 전/후 내용을 시각적으로 비교.

---

## 🏁 구현 마일스톤 (Implementation Milestone)

### **Phase 1: MVP (초경량 뷰어)**
- [ ] `ma <file>` 명령어로 앱 실행 및 파일 로드 기능
- [ ] `FSEvents` 기반 실시간 파일 변경 감지 및 자동 새로고침
- [ ] GFM(GitHub Flavored Markdown) 및 코드 하이라이팅 지원
- [ ] 항상 위(Always-on-Top) 플로팅 윈도우 모드

### **Phase 2: Core Interaction (양방향 연동)**
- [ ] `wait` 플래그 구현 (수정 완료 후 프로세스 제어권 반환)
- [ ] 앱 내 수정 사항의 실시간 원본 파일 반영 (Bi-directional Sync)
- [ ] 최근 문서 사이드바 및 파일 열기 UX 추가
- [ ] 인라인 Diff 하이라이트 표시

### **Phase 3: Polishing & OSS Release**
- [ ] Mermaid(다이어그램) 및 KaTeX(수식) 렌더링 지원
- [ ] 개발자 친화적 테마(Dracula, Nord 등) 및 커스텀 CSS
- [ ] LLM 입력 비용 예측을 위한 토큰 카운터 기능
- [ ] GitHub Release 및 Homebrew Tap 기반 OSS 배포

---

## 🚀 마케팅 타겟 (Target Audience)
1. **Codex CLI / Claude Code / Gemini CLI** 헤비 유저
2. 터미널 환경에서 마크다운 문서화를 즐기는 개발자
3. VS Code보다 가볍고 예쁜 전용 뷰어를 찾는 파워 유저

---

## 📈 기술 스택 추천
* **Language:** Swift 6.0+
* **UI Framework:** SwiftUI
* **Markdown Parser:** `Apple/swift-markdown`
* **IPC:** Unix Domain Sockets or File System Events
