enum RawCodeSyntaxToken {
    case comment
    case keyword
    case number
    case string
    case tag
}

enum RawCodeSyntaxRules {
    static func pattern(for token: RawCodeSyntaxToken, language: CodeHighlightLanguage?) -> String {
        switch token {
        case .comment:
            commentPattern(for: language)
        case .keyword:
            keywordPattern(for: language)
        case .number:
            #"\b\d+(?:\.\d+)?\b"#
        case .string:
            #"`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        case .tag:
            #"</?[A-Za-z][A-Za-z0-9.:-]*"#
        }
    }

    private static func commentPattern(for language: CodeHighlightLanguage?) -> String {
        switch language {
        case .json, .jsonl:
            #"(?!)"#
        case .env, .php, .python, .toml, .yaml:
            #"(?m)//.*$|#.*$"#
        case .css, .less, .sass, .scss:
            #"/\*[\s\S]*?\*/"#
        case .astro, .html, .mdx, .svelte, .vue, .xml:
            #"<!--[\s\S]*?-->"#
        case .jsonc:
            #"(?m)//.*$|/\*[\s\S]*?\*/"#
        case .none:
            #"(?m)//.*$|#.*$"#
        default:
            #"(?m)//.*$"#
        }
    }

    private static func keywordPattern(for language: CodeHighlightLanguage?) -> String {
        let common = "async|await|case|class|const|else|enum|export|false|for|function|if|import|in|interface|let|null|private|public|return|static|switch|this|throw|true|try|type|var|while"
        switch language {
        case .css, .less, .sass, .scss:
            return #"\b(?:align-items|background|border|color|display|flex|font|grid|height|margin|padding|position|width)\b"#
        case .env:
            return #"(?m)^[A-Za-z_][A-Za-z0-9_]*(?=\s*=)"#
        case .astro, .html, .mdx, .svelte, .vue, .xml:
            return #"</?[A-Za-z][A-Za-z0-9.:-]*|[A-Za-z_:][A-Za-z0-9_.:-]*(?=\=)"#
        case .json, .jsonc, .jsonl:
            return #"\b(?:false|null|true)\b|"(?:\\.|[^"\\])*"(?=\s*:)"#
        case .objectiveC:
            return #"\b(?:@interface|@implementation|@end|BOOL|Class|NO|YES|char|const|double|enum|extern|float|id|if|import|int|long|nil|nullptr|return|self|static|struct|switch|typedef|void|while)\b"#
        case .php:
            return #"\b(?:abstract|array|as|class|echo|else|elseif|extends|false|final|foreach|function|if|implements|interface|namespace|new|null|private|protected|public|return|static|string|throw|trait|true|use|while)\b"#
        case .python:
            return #"\b(?:False|None|True|and|async|await|class|def|elif|else|except|finally|for|from|if|import|in|is|lambda|not|or|pass|raise|return|self|try|while|with|yield)\b"#
        case .swift:
            return #"\b(?:actor|as|async|await|case|catch|class|defer|else|enum|extension|false|final|for|func|guard|if|import|in|let|nil|private|protocol|public|return|self|static|struct|switch|throw|throws|true|try|var|while)\b"#
        case .toml:
            return #"\b(?:false|true)\b|(?m)^[A-Za-z0-9_.-]+(?=\s*=)|^\[[^\]]+\]"#
        case .javascript, .jsx, .typescript, .tsx:
            return #"\b(?:\#(common))\b"#
        case .yaml:
            return #"\b(?:false|null|true)\b|(?m)^[\t ]*[A-Za-z0-9_.-]+(?=\s*:)"#
        case .none:
            return #"\b(?:\#(common)|actor|def|func|guard|nil|self|struct|throws)\b"#
        default:
            return #"\b(?:\#(common)|def|fn|func|function|import|module|namespace|package|return|type|use)\b"#
        }
    }
}
