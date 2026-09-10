enum BrandAssetPolicy {
    private struct MonoMark {
        let name: String
        let slug: String
        let geometry: String
    }

    static var rules: [RepositoryTextRule] {
        let icons = "Sources/LittleSwitchUI/Components/BrandIcons/"
        let revision = "4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75"
        let mono = [
            MonoMark(name: "Firecrawl", slug: "firecrawl", geometry: #"M18\.183 7\.67"#),
            MonoMark(name: "Tavily", slug: "tavily", geometry: #"M8\.033 14\.273"#),
            MonoMark(name: "Brave", slug: "brave", geometry: #"M17\.544 2\.375"#),
            MonoMark(name: "Exa", slug: "exa", geometry: #"M3 0h19v1\.791"#),
        ]
        return [
            RepositoryTextRule(
                icons + "ClaudeCodeIcon.swift",
                required: [
                    "https://lobehub\\.com/icons/claudecode", "src/ClaudeCode/components/Color\\.tsx", revision,
                    #"point\(20\.998, 10\.949\)"#,
                ], forbidden: ["Ollama's MIT-licensed"]),
            RepositoryTextRule(
                icons + "ClaudeIcon.swift",
                required: [
                    "https://lobehub\\.com/icons/claude", "src/Claude/components/Color\\.tsx", revision,
                    "#D97757", #"M4\.709 15\.955l4\.72-2\.647"#,
                ]),
            RepositoryTextRule(
                icons + "OpenCodeIcon.swift",
                required: [
                    "https://lobehub\\.com/icons/opencode", "src/OpenCode/components/Mono\\.tsx", revision,
                    #"point\(16, 6\)"#, #"point\(8, 18\)"#, #"point\(20, 22\)"#, #"point\(4, 2\)"#,
                    #"Color\.primary"#, #"FillStyle\(eoFill: true\)"#, #"accessibilityHidden\(true\)"#,
                ]),
            RepositoryTextRule(
                "THIRD_PARTY_NOTICES.md",
                required: [
                    #"Copyright \(c\) 2023 LobeHub"#,
                    "Permission is hereby granted, free of charge, to any person obtaining a copy",
                    #"THE SOFTWARE IS PROVIDED "AS IS""#,
                    #"Claude,\s+Claude Code,\s+OpenAI \(used for Codex\),\s+OpenCode,\s+Firecrawl,\s+Tavily,\s+Brave,\s+Exa,\s+Ollama,\s+and z.ai marks"#,
                    "https://lobehub\\.com/icons/claude", "https://lobehub\\.com/icons/openai",
                    "https://lobehub\\.com/icons/opencode", "https://lobehub\\.com/icons/firecrawl",
                    "https://lobehub\\.com/icons/tavily", "https://lobehub\\.com/icons/brave",
                    "https://lobehub\\.com/icons/exa", revision,
                    "Firecrawl, Tavily, Brave, Exa, Ollama, and z.ai marks",
                ], forbidden: [#"Copyright \(c\) Ollama"#]),
            RepositoryTextRule(
                "tools/build-app.sh",
                required: [#"THIRD_PARTY_NOTICES\.md"#],
                forbidden: ["packaging/licenses", #"\$licenses/ollama"#]),
            RepositoryTextRule("tools/ci/verify-bundle.sh", forbidden: ["Licenses/ollama"]),
        ]
            + mono.map { mark in
                RepositoryTextRule(
                    icons + mark.name + "Icon.swift",
                    required: [
                        "https://lobehub\\.com/icons/" + mark.slug, "src/" + mark.name + "/components/Mono\\.tsx",
                        revision,
                        mark.geometry,
                        #"fill-rule="evenodd""#, "isTemplate = true", #"accessibilityHidden\(true\)"#,
                    ])
            } + documentationRules
    }

    private static var documentationRules: [RepositoryTextRule] {
        [
            RepositoryTextRule(
                "docs/styleguide.md",
                required: [
                    "https://lobehub\\.com/icons", "lobehub/lobe-icons", "SF Symbols", "native SwiftUI",
                    "(?i)pinned commit", "(?i)MIT", "(?i)runtime", "(?i)accessibility", "(?i)trademark",
                    #"settingsMenuPicker\(width:"#, "(?i)regular control size", "(?i)segmented controls remain compact",
                    "(?i)menu selectors on one screen share the same width", #"packaging/AppIcon\.svg"#,
                    #"tools/generate-app-icon\.sh"#, "(?i)light monochrome",
                    #"Sources/LittleSwitchUI/MenuBar/StatusItemIcon\.swift"#,
                    "(?i)18.point canvas", "(?i)1.point stroke", "(?i)template image", "`idle`", "`active`",
                    "(?i)the fill travels", #"(?i)no\s+connector"#, "(?i)provider marks",
                    "https://lobehub\\.com/icons/opencode", "OpenCode mono mark",
                ], forbidden: [#"arrow\.triangle\.swap"#]),
            RepositoryTextRule(
                "docs/product-design.md",
                required: [
                    #"\[`styleguide\.md`\]\(styleguide\.md\)"#,
                    #"four(?: uninterrupted)? 40 pt (?:application )?rows"#,
                    "Claude Desktop", "Claude Code", "Codex", "OpenCode",
                    "OpenCode is its own destination beneath Codex",
                ]),
            RepositoryTextRule(
                "README.md",
                required: [
                    #"~/\.config/opencode/opencode\.json"#, "@ai-sdk/openai", "/v1/responses",
                    "(?i)OpenCode has its own default model.*independent of Codex",
                    "(?i)catalog shared by Codex and OpenCode",
                    "(?i)Restore settings reverts transactionally while preserving other keys",
                ]),
        ]
    }
}
