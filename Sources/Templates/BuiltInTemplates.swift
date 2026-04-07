import Foundation

enum BuiltInTemplates {
    static let all: [Template] = [task, bugReport, codeReview, featureRequest]

    static let task = Template(
        id: "builtin.task",
        name: "Task",
        description: "AI 에이전트에게 작업을 지시하는 구조화된 프롬프트",
        content: """
        # Task: {{task_name}}

        ## Context
        {{context}}

        ## Constraints
        {{constraints}}

        ## Expected Output
        {{expected_output}}
        """,
        variables: [
            TemplateVariable(
                name: "task_name",
                placeholder: "작업 이름을 입력하세요",
                defaultValue: "",
                description: "수행할 작업의 이름"
            ),
            TemplateVariable(
                name: "context",
                placeholder: "작업의 배경과 맥락을 설명하세요",
                defaultValue: "",
                description: "작업 배경 및 관련 정보"
            ),
            TemplateVariable(
                name: "constraints",
                placeholder: "제약 조건이나 주의사항을 나열하세요",
                defaultValue: "",
                description: "작업 수행 시 지켜야 할 제약 조건"
            ),
            TemplateVariable(
                name: "expected_output",
                placeholder: "원하는 결과물의 형태를 설명하세요",
                defaultValue: "",
                description: "기대하는 출력 결과"
            ),
        ]
    )

    static let bugReport = Template(
        id: "builtin.bug_report",
        name: "Bug Report",
        description: "버그 보고를 위한 구조화된 템플릿",
        content: """
        # Bug: {{title}}

        ## 증상
        {{symptom}}

        ## 재현 단계
        {{steps}}

        ## 예상 동작
        {{expected}}

        ## 실제 동작
        {{actual}}

        ## 환경
        {{environment}}
        """,
        variables: [
            TemplateVariable(
                name: "title",
                placeholder: "버그 제목을 입력하세요",
                defaultValue: "",
                description: "버그를 한 줄로 요약"
            ),
            TemplateVariable(
                name: "symptom",
                placeholder: "어떤 문제가 발생했는지 설명하세요",
                defaultValue: "",
                description: "버그 증상 설명"
            ),
            TemplateVariable(
                name: "steps",
                placeholder: "1. 첫 번째 단계\n2. 두 번째 단계",
                defaultValue: "",
                description: "버그 재현 단계"
            ),
            TemplateVariable(
                name: "expected",
                placeholder: "정상적으로 동작해야 하는 방식",
                defaultValue: "",
                description: "예상 동작"
            ),
            TemplateVariable(
                name: "actual",
                placeholder: "실제로 발생한 동작",
                defaultValue: "",
                description: "실제 동작"
            ),
            TemplateVariable(
                name: "environment",
                placeholder: "OS, 버전, 환경 정보 등",
                defaultValue: "",
                description: "재현 환경 정보"
            ),
        ]
    )

    static let codeReview = Template(
        id: "builtin.code_review",
        name: "Code Review",
        description: "코드 리뷰 요청을 위한 구조화된 템플릿",
        content: """
        # Code Review: {{file_path}}

        ## 변경 요약
        {{summary}}

        ## 검토 포인트
        {{review_points}}

        ## 관련 컨텍스트
        {{context}}
        """,
        variables: [
            TemplateVariable(
                name: "file_path",
                placeholder: "리뷰할 파일 경로 (예: src/auth/login.swift)",
                defaultValue: "",
                description: "리뷰 대상 파일 경로"
            ),
            TemplateVariable(
                name: "summary",
                placeholder: "어떤 변경을 했는지 간략히 설명하세요",
                defaultValue: "",
                description: "변경 내용 요약"
            ),
            TemplateVariable(
                name: "review_points",
                placeholder: "특히 검토해 주었으면 하는 부분을 나열하세요",
                defaultValue: "",
                description: "집중 검토 요청 사항"
            ),
            TemplateVariable(
                name: "context",
                placeholder: "변경 배경이나 관련 이슈 등",
                defaultValue: "",
                description: "추가 컨텍스트"
            ),
        ]
    )

    static let featureRequest = Template(
        id: "builtin.feature_request",
        name: "Feature Request",
        description: "새로운 기능 요청을 위한 구조화된 템플릿",
        content: """
        # Feature Request: {{feature_name}}

        ## 동기
        {{motivation}}

        ## 제안 내용
        {{proposal}}

        ## 수용 기준 (Acceptance Criteria)
        {{acceptance_criteria}}

        ## 우선순위
        {{priority}}
        """,
        variables: [
            TemplateVariable(
                name: "feature_name",
                placeholder: "요청하는 기능의 이름",
                defaultValue: "",
                description: "기능 이름"
            ),
            TemplateVariable(
                name: "motivation",
                placeholder: "이 기능이 왜 필요한지 설명하세요",
                defaultValue: "",
                description: "기능 요청 동기"
            ),
            TemplateVariable(
                name: "proposal",
                placeholder: "어떻게 구현되었으면 하는지 설명하세요",
                defaultValue: "",
                description: "기능 제안 내용"
            ),
            TemplateVariable(
                name: "acceptance_criteria",
                placeholder: "- [ ] 기준 1\n- [ ] 기준 2",
                defaultValue: "",
                description: "완료 기준"
            ),
            TemplateVariable(
                name: "priority",
                placeholder: "High / Medium / Low",
                defaultValue: "Medium",
                description: "우선순위"
            ),
        ]
    )
}
