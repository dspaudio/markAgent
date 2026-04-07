/// CLI 인자 파싱 결과를 담는 구조체
struct CLIArguments {
    let filePath: String?
    let waitMode: Bool
    let showHelp: Bool

    static func parse(_ args: [String]) -> CLIArguments {
        var filePath: String?
        var waitMode = false
        var showHelp = false

        // 첫 번째 인자는 실행 파일 경로이므로 건너뜀
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "-w", "--wait":
                waitMode = true
            case "-h", "--help":
                showHelp = true
            default:
                if arg.hasPrefix("-") {
                    // 알 수 없는 플래그는 무시
                    break
                }
                // 위치 인자: 파일 경로 (첫 번째만 사용)
                if filePath == nil {
                    filePath = arg
                }
            }
            index += 1
        }

        return CLIArguments(filePath: filePath, waitMode: waitMode, showHelp: showHelp)
    }

    static var usageText: String {
        """
        MarkAgent — CLI AI 에이전트를 위한 마크다운 뷰어

        사용법:
          ma <file>         마크다운 파일을 뷰어로 열기
          ma -w <file>      Wait 모드: 윈도우 닫으면 프로세스 종료
          ma --help         이 도움말 출력

        옵션:
          -w, --wait        윈도우가 닫힐 때 프로세스를 즉시 종료
          -h, --help        도움말 출력 후 종료

        예시:
          ma README.md
          ma -w PLAN.md
        """
    }
}
