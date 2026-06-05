import Foundation

enum CodeHighlightLanguage: String, Equatable {
    case appleScript
    case arduino
    case astro
    case awk
    case bash
    case basic
    case c
    case clojure
    case cpp
    case csharp
    case css
    case dart
    case delphi
    case diff
    case django
    case dockerfile
    case elixir
    case elm
    case env
    case erlang
    case gherkin
    case go
    case gradle
    case graphql
    case haskell
    case html
    case java
    case javascript
    case jsx
    case json
    case jsonc
    case jsonl
    case julia
    case kotlin
    case latex
    case less
    case lisp
    case lua
    case makefile
    case markdown
    case mathematica
    case matlab
    case mdx
    case nix
    case objectiveC
    case perl
    case php
    case postgresql
    case protobuf
    case python
    case r
    case ruby
    case rust
    case sass
    case scala
    case scss
    case shell
    case sql
    case svelte
    case swift
    case toml
    case typescript
    case tsx
    case visualBasic
    case vue
    case webAssembly
    case xml
    case yaml

    init?(fileURL: URL?) {
        guard let fileURL else { return nil }
        let fileName = fileURL.lastPathComponent.lowercased()
        switch fileName {
        case "dockerfile", "containerfile":
            self = .dockerfile
            return
        case "gemfile":
            self = .ruby
            return
        case "makefile", "gnumakefile":
            self = .makefile
            return
        default:
            break
        }

        if fileName == ".env" || fileName.hasSuffix(".env") {
            self = .env
            return
        }

        switch fileURL.pathExtension.lowercased() {
        case "applescript", "scpt":
            self = .appleScript
        case "ino":
            self = .arduino
        case "astro":
            self = .astro
        case "awk":
            self = .awk
        case "bash":
            self = .bash
        case "bas":
            self = .basic
        case "c":
            self = .c
        case "clj", "cljs", "cljc":
            self = .clojure
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx":
            self = .cpp
        case "cs":
            self = .csharp
        case "css":
            self = .css
        case "dart":
            self = .dart
        case "diff", "patch":
            self = .diff
        case "ex", "exs":
            self = .elixir
        case "elm":
            self = .elm
        case "erl", "hrl":
            self = .erlang
        case "feature":
            self = .gherkin
        case "go":
            self = .go
        case "gradle":
            self = .gradle
        case "graphql", "gql":
            self = .graphql
        case "hs":
            self = .haskell
        case "htm", "html":
            self = .html
        case "java":
            self = .java
        case "h", "o":
            self = .objectiveC
        case "js", "cjs", "mjs":
            self = .javascript
        case "jsx":
            self = .jsx
        case "json":
            self = .json
        case "jsonc":
            self = .jsonc
        case "jsonl":
            self = .jsonl
        case "jl":
            self = .julia
        case "kt", "kts":
            self = .kotlin
        case "tex":
            self = .latex
        case "less":
            self = .less
        case "lisp", "lsp", "cl":
            self = .lisp
        case "lua":
            self = .lua
        case "m", "wl":
            self = .mathematica
        case "matlab":
            self = .matlab
        case "mdx":
            self = .mdx
        case "nix":
            self = .nix
        case "pl", "pm":
            self = .perl
        case "php":
            self = .php
        case "psql", "pgsql":
            self = .postgresql
        case "proto":
            self = .protobuf
        case "py":
            self = .python
        case "r":
            self = .r
        case "rb":
            self = .ruby
        case "rs":
            self = .rust
        case "sass":
            self = .sass
        case "scala", "sc":
            self = .scala
        case "scss":
            self = .scss
        case "sh", "zsh", "fish", "ksh":
            self = .shell
        case "sql":
            self = .sql
        case "svelte":
            self = .svelte
        case "swift":
            self = .swift
        case "toml":
            self = .toml
        case "ts", "cts", "mts":
            self = .typescript
        case "tsx":
            self = .tsx
        case "vue":
            self = .vue
        case "vb":
            self = .visualBasic
        case "wat", "wasm":
            self = .webAssembly
        case "xml":
            self = .xml
        case "yaml", "yml":
            self = .yaml
        default:
            return nil
        }
    }
}

extension CodeHighlightLanguage {
    var usesMarkupTags: Bool {
        switch self {
        case .astro, .html, .jsx, .mdx, .svelte, .tsx, .vue, .xml:
            return true
        default:
            return false
        }
    }
}
