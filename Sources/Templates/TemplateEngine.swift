import Foundation

enum TemplateEngine {
    /// 템플릿의 {{variable}} 패턴을 variables 딕셔너리 값으로 치환
    /// 미입력 변수는 해당 TemplateVariable의 placeholder로 대체
    static func render(_ template: Template, variables: [String: String]) -> String {
        var result = template.content
        let pattern = #"\{\{(\w+)\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let placeholderMap: [String: String] = Dictionary(
            uniqueKeysWithValues: template.variables.map { ($0.name, $0.placeholder) }
        )

        let range = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: range).reversed()

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range(at: 0), in: result) else { continue }

            let key = String(result[keyRange])
            let replacement = variables[key] ?? placeholderMap[key] ?? "{{\(key)}}"
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// 템플릿에서 사용된 변수 이름 목록 추출
    static func extractVariableNames(from content: String) -> [String] {
        let pattern = #"\{\{(\w+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        var seen = Set<String>()
        return matches.compactMap { match -> String? in
            guard let keyRange = Range(match.range(at: 1), in: content) else { return nil }
            let key = String(content[keyRange])
            return seen.insert(key).inserted ? key : nil
        }
    }
}
