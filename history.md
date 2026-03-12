# 개발 히스토리

## 목차

1. [세션 1: 프로젝트 기획 문서 정리 및 Phase 1 구현 계획 수립](#세션-1-프로젝트-기획-문서-정리-및-phase-1-구현-계획-수립)

---

## 전체 타임라인 요약

| 순서 | 내용 | 결과 |
|------|------|------|
| 1 | AGENTS.md 작성 (concept.md 기반, Phase 1 범위) | 프로젝트 개요, 아키텍처, 컨벤션 등 문서화 완료 |
| 2 | Phase 1 세부 구현 계획 수립 | phase1_plan.md — 7 Step 체크리스트 생성 |
| 3 | AGENTS.md에 히스토리 기록 지침 추가 | Workflow Rules 섹션 추가 |
| 4 | 히스토리 기록 형식을 opencode-chat-router 스타일로 변경 | 세션+대화 단위 구분, 목차+타임라인 테이블 |

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
