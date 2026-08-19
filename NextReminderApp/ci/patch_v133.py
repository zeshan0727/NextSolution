#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, 1))


xpost = SOURCES / "XPostGenerator.swift"

# Add the two GTA-specific generator modes.
replace_once(
    xpost,
    '''    case sports
    case qatarGulf''',
    '''    case sports
    case qatarGulf
    case gta6Latest
    case gtaComparisons'''
)
replace_once(
    xpost,
    '''        case .sports: return "Sports"
        case .qatarGulf: return "Qatar & Gulf"''',
    '''        case .sports: return "Sports"
        case .qatarGulf: return "Qatar & Gulf"
        case .gta6Latest: return "GTA 6 Latest"
        case .gtaComparisons: return "GTA Game Comparisons"'''
)
replace_once(
    xpost,
    '''        case .sports: return "Choose a major sports story with broad public interest."
        case .qatarGulf: return "Choose a major Qatar or Gulf-region story with broad public interest."
        }
    }
}''',
    '''        case .sports: return "Choose a major sports story with broad public interest."
        case .qatarGulf: return "Choose a major Qatar or Gulf-region story with broad public interest."
        case .gta6Latest:
            return "Choose a fresh, verified Grand Theft Auto VI or GTA 6 development. Prioritize official Rockstar Games or Take-Two information, regulatory or investor material, and direct reporting from reputable gaming or business publications. Avoid rumors unless the post clearly labels them as unconfirmed and the source is reporting the rumor itself."
        case .gtaComparisons:
            return "Create one rotating Grand Theft Auto series comparison using verified figures. Compare two or more GTA games through one clear angle such as launch revenue, first-day or first-week revenue, first-month purchases or sales, digital downloads, units shipped, sales velocity, or lifetime performance. Never invent an exact first-month or download number. When that period is unavailable, use the nearest verified period and label it precisely."
        }
    }

    var searchWindowLabel: String {
        self == .gtaComparisons ? "verified historical data" : "latest 7 days"
    }
}'''
)

# GTA comparison mode uses verified historical figures rather than forcing a seven-day publication window.
replace_once(
    xpost,
    '''        let instructions = """
        You are the fixed X Post Generator inside Next Reminder. Research real news and create one complete manual-posting package for X.
        Rules:
        - Use web search and select exactly one real story published from \(startText) through \(endText), inclusive.
        - Prefer a reputable direct news article. Do not recycle an older story merely because it was discussed recently.
        - Select for broad impression potential: surprise, useful impact, urgency, novelty, debate and visual potential.
        - Write a curiosity-driven hook, but never invent, misquote, defame, exaggerate beyond the source or present speculation as fact.
        - The post plus hashtags should normally fit within 280 characters.
        - Use 3 to 5 relevant hashtags and avoid spam tags.
        - The first comment must add useful context or a thoughtful question. Do not beg for engagement.
        - Include the direct source title, date and URL.
        - The image prompt must describe an original 16:9 editorial visual with no logos, screenshots, fake quotation text or exact reproduction of a real person's face.
        - The visual must not falsely depict a fictional scene as documentary evidence.
        - Alt text must accurately describe that visual for a screen-reader user.
        - Return only the required structured result.
        """''',
    '''        let researchRule: String
        if topic == .gtaComparisons {
            researchRule = """
            - This is a historical comparison mode and is not restricted to articles published in the latest seven days.
            - Use current web search to verify every numerical claim. Prefer official Rockstar Games or Take-Two releases, earnings material, platform reports, and reputable games-industry or business publications.
            - Choose a comparison angle that can be supported primarily by one reliable source, using additional sources only to cross-check facts.
            - Clearly distinguish revenue, units sold, units shipped, purchases, players, and downloads; never treat them as interchangeable.
            - If an exact first-month figure is not publicly available, use the nearest verified launch period and state that period exactly in the post.
            """
        } else {
            researchRule = """
            - Use web search and select exactly one real story published from \(startText) through \(endText), inclusive.
            - Prefer a reputable direct news article. Do not recycle an older story merely because it was discussed recently.
            """
        }

        let instructions = """
        You are the fixed X Post Generator inside Next Reminder. Research real information and create one complete manual-posting package for X.
        Rules:
        \(researchRule)
        - Select for broad impression potential: surprise, useful impact, urgency, novelty, debate and visual potential.
        - Write a curiosity-driven hook, but never invent, misquote, defame, exaggerate beyond the source or present speculation as fact.
        - The post plus hashtags should normally fit within 280 characters.
        - Use 3 to 5 relevant hashtags and avoid spam tags.
        - The first comment must add useful context or a thoughtful question. Do not beg for engagement.
        - Include the primary direct source title, publication date and URL.
        - The image prompt must describe an original 16:9 editorial visual with no logos, screenshots, fake quotation text or exact reproduction of a real person's face.
        - The visual must not falsely depict a fictional scene as documentary evidence.
        - Alt text must accurately describe that visual for a screen-reader user.
        - Return only the required structured result.
        """'''
)

# Pass recently used GTA angles into the fixed prompt and add a variation seed.
replace_once(
    xpost,
    '''    func generateDraft(topic: XPostTopic, model: XPostTextModel, apiKey: String) async throws -> XPostGenerationResult {''',
    '''    func generateDraft(topic: XPostTopic, model: XPostTextModel, apiKey: String, excludedAngles: [String]) async throws -> XPostGenerationResult {'''
)
replace_once(
    xpost,
    '''        let input = """
        Generate one fresh X post package now.
        Topic preference: \(topic.title).
        \(topic.searchInstruction)
        The user's 90-day objective is 5 million impressions and 500 verified followers, but never promise results and never sacrifice factual accuracy.
        """''',
    '''        let variationSeed = UUID().uuidString
        let excludedText = excludedAngles.isEmpty
            ? "No recent GTA angle needs to be excluded."
            : "Do not repeat these recently generated GTA angles:\n" + excludedAngles.map { "- \($0)" }.joined(separator: "\n")

        let input = """
        Generate one fresh X post package now.
        Topic preference: \(topic.title).
        \(topic.searchInstruction)
        Variation seed: \(variationSeed)
        \(excludedText)
        For GTA comparison mode, rotate among different games and metrics instead of repeatedly comparing the same titles or using the same launch statistic.
        The user's 90-day objective is 5 million impressions and 500 verified followers, but never promise results and never sacrifice factual accuracy.
        """'''
)

# Remember recent GTA angles by mode and avoid charging for repeated results where alternatives exist.
replace_once(
    xpost,
    '''            let result = try await client.generateDraft(topic: topic, model: textModel, apiKey: key)
            let generated = result.draft
            draft = generated''',
    '''            let result = try await client.generateDraft(
                topic: topic,
                model: textModel,
                apiKey: key,
                excludedAngles: recentAngles(for: topic)
            )
            let generated = result.draft
            draft = generated
            rememberAngle(generated, for: topic)'''
)
replace_once(
    xpost,
    '''    func retryVisual(quality: XPostImageQuality) async {''',
    '''    private func recentAngles(for topic: XPostTopic) -> [String] {
        guard topic == .gta6Latest || topic == .gtaComparisons else { return [] }
        return UserDefaults.standard.stringArray(forKey: historyKey(for: topic)) ?? []
    }

    private func rememberAngle(_ draft: XPostDraft, for topic: XPostTopic) {
        guard topic == .gta6Latest || topic == .gtaComparisons else { return }
        let value = "\(draft.storyTitle) — \(draft.selectionReason)"
        var history = recentAngles(for: topic).filter { $0 != value }
        history.insert(value, at: 0)
        UserDefaults.standard.set(Array(history.prefix(8)), forKey: historyKey(for: topic))
    }

    private func historyKey(for topic: XPostTopic) -> String {
        "NextReminder.XPost.RecentAngles.\(topic.rawValue)"
    }

    func retryVisual(quality: XPostImageQuality) async {'''
)

# The command card explains the correct search window for the selected topic.
replace_once(
    xpost,
    '''                    Text("Search window: latest 7 days").font(.caption).foregroundStyle(.secondary)''',
    '''                    Text("Search window: \(topic.searchWindowLabel)").font(.caption).foregroundStyle(.secondary)'''
)

# Version metadata.
project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.2"', 'CFBundleShortVersionString: "1.3.3"')
project_text = project_text.replace('CFBundleVersion: "12"', 'CFBundleVersion: "13"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.2"', 'MARKETING_VERSION: "1.3.3"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "12"', 'CURRENT_PROJECT_VERSION: "13"')
project.write_text(project_text)

settings = SOURCES / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.2 • iOS 16.0+", "Version 1.3.3 • iOS 16.0+"))

for path in SOURCES.glob("*.swift"):
    path.write_text(path.read_text().replace("NextReminder-iOS/1.3.2", "NextReminder-iOS/1.3.3"))

print("Next Reminder v1.3.3 GTA generator topics applied successfully.")
