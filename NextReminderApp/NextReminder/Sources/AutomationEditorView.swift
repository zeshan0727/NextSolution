import PhotosUI
import SwiftUI
import UIKit

struct AutomationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AutomationStore

    let automation: SocialAutomation?

    @State private var title: String
    @State private var platform: AutomationPlatform
    @State private var deliveryMode: AutomationDeliveryMode
    @State private var scheduledAt: Date
    @State private var repeatRule: AutomationRepeat
    @State private var alertOffsets: Set<AutomationAlertOffset>
    @State private var accountID: UUID?
    @State private var recipient: String
    @State private var contentText: String
    @State private var altText: String
    @State private var linkURL: String
    @State private var retryEnabled: Bool
    @State private var maxRetries: Int
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var removeExistingMedia = false
    @State private var isLoadingPhoto = false
    @State private var photoErrorMessage: String?

    init(automation: SocialAutomation?) {
        self.automation = automation
        _title = State(initialValue: automation?.title ?? "")
        _platform = State(initialValue: automation?.platform ?? .whatsapp)
        _deliveryMode = State(initialValue: automation?.deliveryMode ?? .approval)
        _scheduledAt = State(initialValue: automation?.scheduledAt ?? Date().addingTimeInterval(3600))
        _repeatRule = State(initialValue: automation?.repeatRule ?? .never)
        _alertOffsets = State(initialValue: automation?.alertOffsets ?? [.atTime])
        _accountID = State(initialValue: automation?.accountID)
        _recipient = State(initialValue: automation?.recipient ?? "")
        _contentText = State(initialValue: automation?.contentText ?? "")
        _altText = State(initialValue: automation?.altText ?? "")
        _linkURL = State(initialValue: automation?.linkURL ?? "")
        _retryEnabled = State(initialValue: automation?.retryEnabled ?? true)
        _maxRetries = State(initialValue: automation?.maxRetries ?? 3)
    }

    private var compatibleAccounts: [AutomationAccount] {
        store.compatible(platform)
    }

    private var hasMedia: Bool {
        imageData != nil || (automation?.media != nil && !removeExistingMedia)
    }

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasMedia
        let hasRecipient = platform != .whatsapp
            || !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle && hasContent && hasRecipient && scheduledAt > Date().addingTimeInterval(-60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                platformSection
                basicSection
                scheduleSection
                deliveryModeSection
                accountSection
                contentSection
                photoSection
                failureSection
                saveButton
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle(automation == nil ? "New Automation" : "Edit Automation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: platform) { newPlatform in
            if let accountID,
               !store.compatible(newPlatform).contains(where: { $0.id == accountID }) {
                self.accountID = nil
            }
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .alert(
            "Photo Error",
            isPresented: Binding(
                get: { photoErrorMessage != nil },
                set: { if !$0 { photoErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoErrorMessage ?? "The photo could not be loaded.")
        }
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Platform")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                ForEach(AutomationPlatform.allCases) { option in
                    Button {
                        platform = option
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: option.symbol)
                                .font(.title2)
                            Text(option.title)
                                .font(.caption.bold())
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(platform == option ? Color.white : option.color)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(platform == option ? option.color : option.color.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automation")
            TextField("Automation title", text: $title)
                .padding(14)
                .nextCard()

            if platform == .whatsapp {
                TextField("Recipient number with country code", text: $recipient)
                    .keyboardType(.phonePad)
                    .padding(14)
                    .nextCard()
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Schedule")
            DatePicker(
                "Date and time",
                selection: $scheduledAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .padding(14)
            .nextCard()

            Menu {
                ForEach(AutomationRepeat.allCases) { option in
                    Button(option.title) { repeatRule = option }
                }
            } label: {
                settingsRow(icon: "repeat", title: "Repeat", value: repeatRule.title)
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 9)], spacing: 9) {
                ForEach(AutomationAlertOffset.allCases) { offset in
                    Button {
                        toggleAlert(offset)
                    } label: {
                        Label(
                            offset.title,
                            systemImage: alertOffsets.contains(offset) ? "checkmark.circle.fill" : "bell"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(alertOffsets.contains(offset) ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(alertOffsets.contains(offset) ? Color.nextOrange : Color.nextCard)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deliveryModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Delivery Mode")
            ForEach(AutomationDeliveryMode.allCases) { option in
                Button {
                    deliveryMode = option
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: option.symbol)
                            .foregroundStyle(deliveryMode == option ? Color.nextOrange : Color.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.headline)
                            Text(option.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: deliveryMode == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(deliveryMode == option ? Color.nextOrange : Color.secondary)
                    }
                    .padding(14)
                    .nextCard()
                }
                .buttonStyle(.plain)
            }

            if deliveryMode == .automaticCloud {
                let configured = store.cloudConfiguration.isConfigured
                Label(
                    configured ? "Automation server configured" : "Automation server setup required",
                    systemImage: configured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(configured ? Color.green : Color.orange)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Account", trailing: "Settings")

            if compatibleAccounts.isEmpty {
                NavigationLink {
                    AutomationConnectionsView()
                } label: {
                    settingsRow(
                        icon: "person.badge.plus",
                        title: "Add compatible account",
                        value: platform.shortTitle
                    )
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Button("No account") { accountID = nil }
                    ForEach(compatibleAccounts) { account in
                        Button(account.displayName) { accountID = account.id }
                    }
                } label: {
                    settingsRow(
                        icon: "person.crop.circle.fill",
                        title: "Publishing account",
                        value: store.account(accountID)?.displayName ?? "Select account"
                    )
                }
                .buttonStyle(.plain)
            }

            if platform == .instagramStory,
               let account = store.account(accountID),
               account.accountType != .instagramBusiness {
                Text("Automatic Instagram Stories require an Instagram Business account.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: platform.contentPrompt)
            TextEditor(text: $contentText)
                .frame(minHeight: 145)
                .scrollContentBackground(.hidden)
                .padding(10)
                .nextCard()

            TextField("Optional link", text: $linkURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(14)
                .nextCard()

            if platform != .whatsapp {
                TextField("Image alt text (optional)", text: $altText)
                    .padding(14)
                    .nextCard()
            }

            if platform == .xPost {
                Text("Text length: \(contentText.count) characters")
                    .font(.caption)
                    .foregroundStyle(contentText.count > 280 ? Color.orange : Color.secondary)
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Photo", trailing: "Optional")
            selectedImagePreview

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(
                    isLoadingPhoto ? "Loading…" : "Choose Photo",
                    systemImage: "photo.badge.plus"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoadingPhoto)

            if hasMedia {
                Button(role: .destructive) {
                    imageData = nil
                    selectedPhoto = nil
                    removeExistingMedia = true
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedImagePreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            imagePreview(image)
        } else if let automation,
                  automation.media != nil,
                  !removeExistingMedia,
                  let url = store.mediaURL(automation),
                  let image = UIImage(contentsOfFile: url.path) {
            imagePreview(image)
        }
    }

    private func imagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var failureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Failure Handling")
            Toggle("Retry temporary failures", isOn: $retryEnabled)
                .padding(14)
                .nextCard()
            if retryEnabled {
                Stepper("Maximum retries: \(maxRetries)", value: $maxRetries, in: 1...5)
                    .padding(14)
                    .nextCard()
            }
        }
    }

    private var saveButton: some View {
        Button(automation == nil ? "Create Automation" : "Save Changes") {
            saveAutomation()
        }
        .buttonStyle(OrangeActionButtonStyle())
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.nextOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .nextCard()
    }

    private func toggleAlert(_ offset: AutomationAlertOffset) {
        if alertOffsets.contains(offset) {
            alertOffsets.remove(offset)
        } else {
            alertOffsets.insert(offset)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressed = image.jpegData(compressionQuality: 0.82) else {
                throw AutomationError.invalidResponse
            }
            guard compressed.count <= 10_000_000 else {
                throw AutomationError.mediaTooLarge
            }
            imageData = compressed
            removeExistingMedia = false
        } catch {
            photoErrorMessage = error.localizedDescription
        }
    }

    private func saveAutomation() {
        let cleanedAlerts: Set<AutomationAlertOffset> = alertOffsets.isEmpty ? [.atTime] : alertOffsets
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAltText = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLink = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing = automation {
            existing.title = cleanedTitle
            existing.platform = platform
            existing.deliveryMode = deliveryMode
            existing.scheduledAt = scheduledAt
            existing.timeZoneIdentifier = TimeZone.current.identifier
            existing.repeatRule = repeatRule
            existing.alertOffsets = cleanedAlerts
            existing.accountID = accountID
            existing.recipient = cleanedRecipient
            existing.contentText = cleanedText
            existing.altText = cleanedAltText
            existing.linkURL = cleanedLink
            existing.retryEnabled = retryEnabled
            existing.maxRetries = maxRetries
            store.update(existing, image: imageData, removeMedia: removeExistingMedia)
        } else {
            let newAutomation = SocialAutomation(
                title: cleanedTitle,
                platform: platform,
                deliveryMode: deliveryMode,
                scheduledAt: scheduledAt,
                repeatRule: repeatRule,
                alertOffsets: cleanedAlerts,
                accountID: accountID,
                recipient: cleanedRecipient,
                contentText: cleanedText,
                altText: cleanedAltText,
                linkURL: cleanedLink,
                retryEnabled: retryEnabled,
                maxRetries: maxRetries
            )
            store.add(newAutomation, image: imageData)
        }
        dismiss()
    }
}
