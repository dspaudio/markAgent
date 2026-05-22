# MarkAgent 릴리즈 빌드 워크플로우

이 명령은 **markAgent 프로젝트 전용**입니다.

사용 예시:

```text
/release-build
/release-build 1.1.2
```

버전 인자(`$ARGUMENTS`)가 있으면 그 버전을 사용하고, 비어 있으면 현재 `Sources/App/Info.plist`의 `CFBundleShortVersionString`을 읽어 **patch + 1** 버전을 계산한 뒤 다음 작업을 **순서대로 끝까지** 수행하세요.

---

## 목표

버전을 올리고, README와 `history.md`를 이번 변경분에 맞게 갱신한 뒤:

1. 릴리즈 빌드 생성
2. GitHub Release 업로드
3. 커밋 & 푸시
4. `main` 대상 PR 생성
5. PR 머지

까지 한 번에 진행합니다.

---

## 필수 규칙

1. **버전 결정 규칙**
   - `$ARGUMENTS`가 있으면 해당 버전을 그대로 사용하세요.
   - `$ARGUMENTS`가 비어 있으면 현재 버전을 읽어 **patch + 1**을 자동 계산하세요.
   - major/minor는 자동 추론하지 말고, 사용자가 명시 버전을 줄 때만 올리세요.

2. **히스토리 기록 필수**
   - 커밋/푸시 전에 반드시 `history.md`를 업데이트하세요.
   - 이 프로젝트는 새 세션을 **append** 방식으로 기록합니다.
   - 목차와 타임라인 요약 테이블도 함께 갱신하세요.

3. **README 기능 소개 반영**
   - `README.md`의 Features / 주요 기능 섹션에 이번 릴리즈에서 실제 추가된 기능만 반영하세요.
   - 과장하거나 구현되지 않은 내용은 쓰지 마세요.

4. **버전 반영 위치**
   - `Sources/App/Info.plist`
   - `CFBundleVersion`
   - `CFBundleShortVersionString`

5. **릴리즈 빌드 검증 필수**
   - `swift test`
   - `scripts/bundle.sh release`
   - zip 생성 및 SHA-256 계산

6. **Git 작업은 원자적으로**
   - 의미가 다른 변경은 여러 커밋으로 나누세요.
   - 이 프로젝트는 semantic prefix 스타일을 우선 사용합니다.
   - 예: `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`

7. **GitHub 작업**
   - Release tag는 `v<version>` 형식
   - PR base는 `main`, head는 현재 작업 브랜치(보통 `dev`)
   - PR 생성 후 머지까지 완료하세요.

---

## 수행 절차

### 1. 현재 상태 점검

- git 상태 확인
- 최근 커밋 메시지 스타일 확인
- 현재 브랜치와 upstream 확인
- 미커밋 변경 범위 파악

### 2. 문서/버전 업데이트

- `Sources/App/Info.plist` → 버전 갱신
- `README.md` → 새 기능 반영
- `history.md` → 새 세션 기록 추가, 목차/타임라인 갱신

### 3. 검증

- `swift build`
- `swift test`
- 필요 시 추가 관련 검증 수행

### 4. 커밋

변경 범위에 따라 여러 커밋으로 나누세요. 최소 기준:

- 기능/버그 수정
- 버전 갱신
- 문서 업데이트

모든 커밋 메시지에는 이 프로젝트의 기존 스타일을 따르세요.

### 5. 릴리즈 빌드

- `scripts/bundle.sh release`
- `.build/MarkAgent.app` 생성 확인
- `MarkAgent-v<version>.zip` 생성
- SHA-256 계산

### 6. 원격 반영

- 현재 브랜치 푸시
- `gh release create` 또는 기존 tag면 적절히 갱신
- 릴리즈 노트에 핵심 변경점 + Verification + SHA-256 포함

### 7. PR & 머지

- `gh pr create --base main --head <branch>`
- PR 본문에 Summary / Verification 포함
- PR 머지 완료

### 8. 최종 보고

다음을 짧게 정리하세요:

- 생성된 커밋들
- Release URL
- PR URL
- 사용한 SHA-256
- 남은 로컬 산출물(zip 등) 존재 여부

---

## 출력 톤

- 불필요한 장황함 없이 결과 중심
- 릴리즈 URL, PR URL, SHA-256은 빠뜨리지 말 것
- 실패 시 어느 단계에서 막혔는지와 현재 상태를 정확히 적을 것

---

## 릴리즈 대상 버전

- 명시 인자: `$ARGUMENTS`
- 인자 없음: 현재 버전 기준 `patch + 1`
