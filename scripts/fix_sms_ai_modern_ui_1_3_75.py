from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


def matching_brace(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    escape = False
    i = open_index
    while i < len(text):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise RuntimeError("Could not find matching brace")


def replace_navigation_link_containing(text: str, marker: str, replacement: str) -> str:
    marker_index = text.find(marker)
    if marker_index < 0:
        raise RuntimeError(f"Navigation marker not found: {marker}")
    start = text.rfind("NavigationLink {", 0, marker_index)
    if start < 0:
        raise RuntimeError(f"NavigationLink start not found for {marker}")
    destination_open = text.find("{", start)
    destination_close = matching_brace(text, destination_open)
    label_index = text.find("label:", destination_close)
    if label_index < 0:
        raise RuntimeError(f"NavigationLink label not found for {marker}")
    label_open = text.find("{", label_index)
    label_close = matching_brace(text, label_open)
    return text[:start] + replacement + text[label_close + 1:]


# ---------------------------------------------------------------------------
# Version: app 1.3.75 / build 83. Daemon is intentionally unchanged.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.74"', 'MARKETING_VERSION: "1.3.75"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "82"', 'CURRENT_PROJECT_VERSION: "83"')


# ---------------------------------------------------------------------------
# Settings navigation: modern AI page and remove unnecessary intermediate pages
# for Automatic Bank SMS and Vendor Rules.
# ---------------------------------------------------------------------------
settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings = settings.replace(
    'LabeledContent("Version", value: "1.3.74")',
    'LabeledContent("Version", value: "1.3.75")',
    1,
)

settings = replace_navigation_link_containing(
    settings,
    'SettingsSectionPage(title: "AI")',
    '''NavigationLink {
                        ModernAISettingsView()
                    } label: {
                        SettingsHomeLinkLabel(title: "AI", subtitle: "API keys, models and AI access", icon: "brain.head.profile", tint: AppTheme.purple)
                    }''',
)

settings = replace_navigation_link_containing(
    settings,
    'SettingsSectionPage(title: "Automatic Bank SMS")',
    '''NavigationLink {
                        SMSImportConsoleView()
                    } label: {
                        SettingsHomeLinkLabel(title: "Automatic Bank SMS", subtitle: "Scheduled SMS import and review", icon: "message.badge.filled.fill", tint: AppTheme.orange)
                    }''',
)

settings = replace_navigation_link_containing(
    settings,
    'SettingsSectionPage(title: "Vendor Rules")',
    '''NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsHomeLinkLabel(title: "Vendor Rules", subtitle: "Merchant categorization rules", icon: "tag.fill", tint: AppTheme.purple)
                    }''',
)

modern_ai = r'''

private struct ModernAISettingsView: View {
    @State private var deepSeekAPIKey = ""
    @State private var deepSeekConnected = DeepSeekService.shared.hasAPIKey
    @State private var testingDeepSeek = false
    @State private var deepSeekStatus = ""

    @State private var openAIAPIKey = ""
    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
    @State private var openAIStatus = ""

    @AppStorage("OpenAIModel") private var openAIModel = "gpt-4.1-nano"
    @AppStorage("DeepSeekModel") private var deepSeekModel = "deepseek-v4-flash"
    @State private var notice: SettingsNotice?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                openAICard
                deepSeekCard
                privacyCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            openAIConnected = OpenAIService.shared.hasAPIKey
            deepSeekConnected = DeepSeekService.shared.hasAPIKey
            if openAIConnected && openAIStatus.isEmpty { openAIStatus = "Ready for OpenAI Chat and SMS AI Helper" }
            if deepSeekConnected && deepSeekStatus.isEmpty { deepSeekStatus = "Ready for DeepSeek insights" }
        }
        .alert(item: $notice) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 58, height: 58)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Ledger AI")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Connections, models and privacy in one place")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
            }

            HStack(spacing: 8) {
                AIStatusPill(title: "OpenAI", connected: openAIConnected)
                AIStatusPill(title: "DeepSeek", connected: deepSeekConnected)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppTheme.purple, AppTheme.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: AppTheme.purple.opacity(0.16), radius: 16, y: 8)
    }

    private var openAICard: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerHeader(
                title: "OpenAI",
                subtitle: "Chat + SMS AI Helper",
                icon: "sparkles",
                connected: openAIConnected,
                tint: AppTheme.green
            )

            OpenAIAPIKeyEntryView(apiKey: $openAIAPIKey, connected: openAIConnected)

            VStack(alignment: .leading, spacing: 7) {
                Text("Text Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("OpenAI Text Model", selection: $openAIModel) {
                    ForEach(OpenAIService.selectableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 9) {
                Button {
                    saveOpenAIKey()
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    testOpenAIConnection()
                } label: {
                    if testingOpenAI {
                        ProgressView()
                    } else {
                        Label("Test", systemImage: "network")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!openAIConnected || testingOpenAI)

                if openAIConnected {
                    Button(role: .destructive) {
                        OpenAIService.shared.deleteAPIKey()
                        openAIAPIKey = ""
                        openAIConnected = false
                        openAIStatus = "Disconnected"
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !openAIStatus.isEmpty {
                Label(openAIStatus, systemImage: openAIConnected ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(openAIConnected ? AppTheme.green : .secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }

    private var deepSeekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerHeader(
                title: "DeepSeek",
                subtitle: "Insights + recommendations",
                icon: "waveform.path.ecg.rectangle",
                connected: deepSeekConnected,
                tint: AppTheme.purple
            )

            SecureField(
                deepSeekConnected ? "Enter replacement DeepSeek key" : "DeepSeek API key",
                text: $deepSeekAPIKey
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("DeepSeek Model", selection: $deepSeekModel) {
                    Text("V4 Flash · Faster").tag("deepseek-v4-flash")
                    Text("V4 Pro · Deeper").tag("deepseek-v4-pro")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 9) {
                Button {
                    saveDeepSeekKey()
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    testDeepSeekConnection()
                } label: {
                    if testingDeepSeek {
                        ProgressView()
                    } else {
                        Label("Test", systemImage: "network")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!deepSeekConnected || testingDeepSeek)

                if deepSeekConnected {
                    Button(role: .destructive) {
                        DeepSeekService.shared.deleteAPIKey()
                        deepSeekAPIKey = ""
                        deepSeekConnected = false
                        deepSeekStatus = "Disconnected"
                    } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !deepSeekStatus.isEmpty {
                Label(deepSeekStatus, systemImage: deepSeekConnected ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(deepSeekConnected ? AppTheme.green : .secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Privacy")
                        .font(.headline)
                    Text("You stay in control of what is sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            AIInfoRow(icon: "iphone", text: "Local Ledger Search stays on this iPhone.")
            AIInfoRow(icon: "message.fill", text: "SMS AI Helper starts with only the latest 10 review messages for AI analysis.")
            AIInfoRow(icon: "hand.tap.fill", text: "More SMS data requires Load 10 More inside the SMS review screen.")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func providerHeader(
        title: String,
        subtitle: String,
        icon: String,
        connected: Bool,
        tint: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AIStatusPill(title: connected ? "Connected" : "Offline", connected: connected)
        }
    }

    private func saveOpenAIKey() {
        let value = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try OpenAIService.shared.saveAPIKey(value)
            openAIConnected = OpenAIService.shared.hasAPIKey
            if openAIConnected {
                openAIAPIKey = ""
                openAIStatus = "Saved securely · SMS AI Helper uses this same connection"
                notice = SettingsNotice(title: "OpenAI Connected", message: "The OpenAI key was saved securely and is ready for Chat and SMS AI Helper.")
                Task { await SMSOpenAIAutoRecoveryCoordinator.shared.processPending() }
            } else {
                openAIStatus = "Save verification failed"
            }
        } catch {
            openAIConnected = OpenAIService.shared.hasAPIKey
            openAIStatus = "Save failed"
            notice = SettingsNotice(title: "OpenAI Error", message: error.localizedDescription)
        }
    }

    private func testOpenAIConnection() {
        testingOpenAI = true
        Task {
            do {
                _ = try await OpenAIService.shared.request(
                    messages: [OpenAIMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: openAIModel,
                    maxTokens: 20
                )
                await MainActor.run {
                    testingOpenAI = false
                    openAIConnected = true
                    openAIStatus = "Connection test passed"
                }
            } catch {
                await MainActor.run {
                    testingOpenAI = false
                    openAIStatus = "Connection test failed"
                    notice = SettingsNotice(title: "OpenAI Test Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func saveDeepSeekKey() {
        let value = deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try DeepSeekService.shared.saveAPIKey(value)
            deepSeekConnected = true
            deepSeekAPIKey = ""
            deepSeekStatus = "Saved securely"
            notice = SettingsNotice(title: "DeepSeek Connected", message: "The DeepSeek key was saved securely and is ready for insights.")
        } catch {
            deepSeekConnected = DeepSeekService.shared.hasAPIKey
            deepSeekStatus = "Save failed"
            notice = SettingsNotice(title: "DeepSeek Error", message: error.localizedDescription)
        }
    }

    private func testDeepSeekConnection() {
        testingDeepSeek = true
        Task {
            do {
                _ = try await DeepSeekService.shared.request(
                    messages: [DeepSeekMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: deepSeekModel,
                    maxTokens: 20
                )
                await MainActor.run {
                    testingDeepSeek = false
                    deepSeekConnected = true
                    deepSeekStatus = "Connection test passed"
                }
            } catch {
                await MainActor.run {
                    testingDeepSeek = false
                    deepSeekStatus = "Connection test failed"
                    notice = SettingsNotice(title: "DeepSeek Test Failed", message: error.localizedDescription)
                }
            }
        }
    }
}

private struct AIStatusPill: View {
    let title: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connected ? AppTheme.green : Color.secondary.opacity(0.7))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
    }
}

private struct AIInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.purple)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
'''

if "private struct ModernAISettingsView" in settings:
    raise RuntimeError("ModernAISettingsView already present")
settings += modern_ai
write(settings_path, settings)


# ---------------------------------------------------------------------------
# SMS AI cache: provide one explicit, safe clear operation. It clears only AI
# suggestions/status metadata. It never deletes SMS, drafts, or ledger entries.
# ---------------------------------------------------------------------------
service_path = "DailyLedger/Services/SMSAIRecognitionService.swift"
service = read(service_path)
service_anchor = '''    private static func cacheKey(_ id: UUID) -> String {
'''
clear_method = r'''    static func clearAllCachedResults() {
        let defaults = UserDefaults.standard
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys where key.hasPrefix("SMSAIRecognitionV1.") {
            defaults.removeObject(forKey: key)
        }
        [
            "SMSAILastProviderV1",
            "SMSAILastSuccessV1",
            "SMSAILastTypeV1",
            "SMSAILastConfidenceV1",
            "SMSAILastErrorV1",
            "SMSAILastAttemptV1",
            "SMSOpenAIWorkerStatusV2",
            "SMSOpenAILastErrorV1",
            "SMSOpenAILastSuccessAtV1",
            "SMSOpenAILastResultTypeV1"
        ].forEach { defaults.removeObject(forKey: $0) }
        let generation = defaults.integer(forKey: "SMSLatest15AIClearGeneration") + 1
        defaults.set(generation, forKey: "SMSLatest15AIClearGeneration")
        defaults.set(Date().timeIntervalSince1970, forKey: "SMSLatest15AIClearedAt")
        NotificationCenter.default.post(name: statusChanged, object: nil)
    }

'''
if service_anchor not in service:
    raise RuntimeError("SMS AI cache anchor not found")
service = service.replace(service_anchor, clear_method + service_anchor, 1)
write(service_path, service)


# ---------------------------------------------------------------------------
# Latest SMS review AI: default AI window = latest 10, manual +10 expansion,
# dedicated clear action, and prevent per-row Ask AI from bypassing the window.
# ---------------------------------------------------------------------------
review_path = "DailyLedger/Views/SMSLatest15ReviewView.swift"
review = read(review_path)

state_anchor = '''    @State private var notice: String?
'''
state_replacement = '''    @State private var notice: String?
    @State private var aiVisibleLimit = 10
    @AppStorage("SMSLatest15AIClearGeneration") private var aiClearGeneration = 0
'''
if review.count(state_anchor) != 1:
    raise RuntimeError("SMS review state anchor not found")
review = review.replace(state_anchor, state_replacement, 1)

review_controls_anchor = '''                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(testingConnection ? "Testing…" : "Test OpenAI", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(testingConnection || !OpenAIService.shared.hasAPIKey)

                    Button {
                        Task { await analyzePending() }
                    } label: {
                        Label(aiRunning ? "Analyzing…" : "Analyze Pending", systemImage: "sparkles")
                    }
                    .disabled(aiRunning || pendingItems.isEmpty || !OpenAIService.shared.hasAPIKey)
                }
'''
review_controls_new = '''                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(testingConnection ? "Testing…" : "Test OpenAI", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(testingConnection || !OpenAIService.shared.hasAPIKey)

                    Button {
                        Task { await analyzePending() }
                    } label: {
                        Label(aiRunning ? "Analyzing…" : "Analyze Available", systemImage: "sparkles")
                    }
                    .disabled(aiRunning || aiBatchCandidates.isEmpty || !OpenAIService.shared.hasAPIKey)
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(
                        "AI Access Window",
                        value: "Latest \\(min(aiVisibleLimit, pendingItems.count)) of \\(pendingItems.count) pending"
                    )
                    Text("SMS AI starts with only the latest 10 pending review messages. Loading more always requires your tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 9) {
                        if pendingItems.count > aiVisibleLimit {
                            Button {
                                aiVisibleLimit = min(aiVisibleLimit + 10, pendingItems.count)
                            } label: {
                                Label("Load 10 More for AI", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            clearAIResults(showNotice: true, clearSharedCache: true)
                        } label: {
                            Label("Clear SMS AI Results", systemImage: "trash.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                }
'''
if review.count(review_controls_anchor) != 1:
    raise RuntimeError("SMS review top controls anchor not found")
review = review.replace(review_controls_anchor, review_controls_new, 1)

review = review.replace(
    '''        .onAppear {
            reload()
''',
    '''        .onAppear {
            aiVisibleLimit = 10
            reload()
''',
    1,
)

alert_anchor = '''        .alert("SMS Review", isPresented: Binding(
'''
change_block = '''        .onChange(of: aiClearGeneration) { _ in
            clearAIResults(showNotice: false, clearSharedCache: false)
        }
'''
if alert_anchor not in review:
    raise RuntimeError("SMS review alert anchor missing")
review = review.replace(alert_anchor, change_block + alert_anchor, 1)

pending_block = '''    private var pendingItems: [SMSLatestReviewMessage] {
        items.filter { SMSLatest15ReviewService.disposition(for: $0.id) == nil }
    }
'''
pending_new = '''    private var pendingItems: [SMSLatestReviewMessage] {
        items.filter { SMSLatest15ReviewService.disposition(for: $0.id) == nil }
    }

    private var aiWindowItems: [SMSLatestReviewMessage] {
        Array(pendingItems.prefix(max(aiVisibleLimit, 0)))
    }

    private var aiWindowIDs: Set<UUID> {
        Set(aiWindowItems.map(\\.id))
    }

    private var aiBatchCandidates: [SMSLatestReviewMessage] {
        aiWindowItems.filter { results[$0.id] == nil }
    }
'''
if review.count(pending_block) != 1:
    raise RuntimeError("SMS pendingItems block missing")
review = review.replace(pending_block, pending_new, 1)

review = review.replace(
    '''        let batch = pendingItems
''',
    '''        let batch = aiBatchCandidates
''',
    1,
)

ask_ai_disabled = '''                            .disabled(aiRunning || !OpenAIService.shared.hasAPIKey)
'''
ask_ai_replacement = '''                            .disabled(aiRunning || !OpenAIService.shared.hasAPIKey || !aiWindowIDs.contains(item.id))
'''
if review.count(ask_ai_disabled) != 1:
    raise RuntimeError(f"Expected one per-row Ask AI disabled anchor, found {review.count(ask_ai_disabled)}")
review = review.replace(ask_ai_disabled, ask_ai_replacement, 1)

reload_anchor = '''    private func reload() {
        items = SMSLatest15ReviewService.load()
    }
'''
clear_function = r'''    private func clearAIResults(showNotice: Bool, clearSharedCache: Bool) {
        results.removeAll()
        aiLog.removeAll()
        aiRunning = false
        aiCurrent = 0
        aiTotal = 0
        aiVisibleLimit = 10
        if clearSharedCache {
            SMSAIRecognitionService.clearAllCachedResults()
        }
        if showNotice {
            notice = "SMS AI results were cleared. Collected messages, review decisions, drafts, and ledger transactions were not deleted."
        }
    }

'''
if reload_anchor not in review:
    raise RuntimeError("SMS review reload anchor missing")
review = review.replace(reload_anchor, reload_anchor + "\n" + clear_function, 1)
write(review_path, review)


# ---------------------------------------------------------------------------
# SMS Import Console: place the clear control where the user expects it, directly
# beside the SMS AI Helper status. The Latest 15 collection itself remains intact.
# ---------------------------------------------------------------------------
console_path = "DailyLedger/Views/SMSImportConsoleView.swift"
console = read(console_path)
old_ai_helper = '''                LabeledContent(
                    "AI Helper",
                    value: OpenAIService.shared.hasAPIKey ? "Ready · Test inside Latest 15 Review" : "OpenAI API required"
                )
                Text("Manual collection always shows the latest 15 incoming messages with their recovered full text. OpenAI is optional assistance inside Latest 15 Review; it never approves or records a message by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
'''
new_ai_helper = '''                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("SMS AI Helper", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(OpenAIService.shared.hasAPIKey ? "Ready" : "API required")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OpenAIService.shared.hasAPIKey ? AppTheme.green : .secondary)
                    }
                    Text("AI can analyze only the latest 10 pending review messages by default. Use Load 10 More inside Latest 15 Review when you want to expose more messages to AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        clearSMSAIHelperResults()
                    } label: {
                        Label("Clear AI Helper Results", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)
'''
if console.count(old_ai_helper) != 1:
    raise RuntimeError("SMS Import Console AI Helper block not found")
console = console.replace(old_ai_helper, new_ai_helper, 1)

start_ai_anchor = '''    private func startAIRecognitionIfNeeded() {
'''
console_clear = r'''    private func clearSMSAIHelperResults() {
        SMSAIRecognitionService.clearAllCachedResults()
        aiProcessedCount = 0
        notice = "SMS AI Helper results were cleared. Latest 15 messages, drafts, review decisions, and ledger transactions were left unchanged."
        refresh()
    }

'''
if start_ai_anchor not in console:
    raise RuntimeError("SMS console AI function anchor not found")
console = console.replace(start_ai_anchor, console_clear + start_ai_anchor, 1)
write(console_path, console)

print("Prepared Next Ledger 1.3.75: SMS AI uses a 10-message default window with manual +10, dedicated clear controls in SMS, direct Settings navigation for SMS/Vendor Rules, and a modern AI settings page.")
