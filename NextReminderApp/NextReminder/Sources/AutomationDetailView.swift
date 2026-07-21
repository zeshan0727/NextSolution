import SwiftUI
import UIKit

struct AutomationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AutomationStore

    let automationID: UUID

    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showCompletionConfirmation = false
    @State private var isPublishing = false

    private var automation: SocialAutomation? {
        store.automation(automationID)
    }

    var body: some View {
        Group {
            if let automation {
                automationContent(automation)
            } else {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "Automation not found",
                    message: "This automation may have been deleted."
                )
            }
        }
        .onAppear {
            store.refreshDueStatuses()
        }
    }

    private func automationContent(_ automation: SocialAutomation) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                header(automation)
                preparedContent(automation)
                details(automation)
                actionSection(automation)
                historySection(automation)
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Automation Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                AutomationEditorView(automation: automation)
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            showCompletionConfirmation = true
        }) {
            ActivityViewController(items: shareItems)
        }
        .confirmationDialog(
            automation.platform == .whatsapp
                ? "Was the message sent?"
                : "Was the content published?",
            isPresented: $showCompletionConfirmation,
            titleVisibility: .visible
        ) {
            Button(automation.platform == .whatsapp ? "Yes, Mark Sent" : "Yes, Mark Published") {
                store.markAssistedComplete(automation)
            }
            Button("Not Yet", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this automation?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(automation)
                dismiss()
            }
        }
    }

    private func header(_ automation: SocialAutomation) -> some View {
        VStack(spacing: 14) {
            Image(systemName: automation.platform.symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(automation.platform.color)
                .frame(width: 82, height: 82)
                .background(automation.platform.color.opacity(0.14), in: Circle())

            Text(automation.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack {
                AutomationStatusBadge(status: automation.status)
                AutomationModeBadge(mode: automation.deliveryMode)
            }

            Text(automation.scheduledAt.formatted(date: .long, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .nextCard()
    }

    private func preparedContent(_ automation: SocialAutomation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Prepared Content")

            if automation.media != nil {
                AutomationMediaView(url: store.mediaURL(automation), size: 220)
                    .frame(maxWidth: .infinity)
            }

            if !automation.contentText.isEmpty {
                Text(automation.contentText)
                    .textSelection(.enabled)
            }

            if !automation.linkURL.isEmpty {
                Label(automation.linkURL, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
            }

            if automation.platform == .whatsapp {
                detailRow(icon: "person.fill", title: "Recipient", value: automation.recipient)
            }

            if !automation.altText.isEmpty {
                detailRow(icon: "text.bubble", title: "Alt text", value: automation.altText)
            }
        }
        .padding(16)
        .nextCard()
    }

    private func details(_ automation: SocialAutomation) -> some View {
        VStack(spacing: 0) {
            detailRow(
                icon: "clock.fill",
                title: "Scheduled",
                value: automation.scheduledAt.formatted(date: .abbreviated, time: .shortened)
            )
            Divider().opacity(0.2)
            detailRow(icon: "repeat", title: "Repeat", value: automation.repeatRule.title)
            Divider().opacity(0.2)
            detailRow(
                icon: "person.crop.circle",
                title: "Account",
                value: store.account(automation.accountID)?.displayName ?? "Not selected"
            )

            if let error = automation.lastError {
                Divider().opacity(0.2)
                detailRow(icon: "exclamationmark.triangle.fill", title: "Last Error", value: error)
            }
        }
        .nextCard()
    }

    @ViewBuilder
    private func actionSection(_ automation: SocialAutomation) -> some View {
        if !automation.status.isFinished {
            VStack(spacing: 12) {
                if automation.status == .paused {
                    Button {
                        store.resume(automation)
                    } label: {
                        Label("Resume Automation", systemImage: "play.fill")
                    }
                    .buttonStyle(OrangeActionButtonStyle())
                } else {
                    publishingButtons(automation)
                    secondaryButtons(automation)
                }
            }
        }
    }

    @ViewBuilder
    private func publishingButtons(_ automation: SocialAutomation) -> some View {
        let canCloudPublish = store.cloudConfiguration.isConfigured
            && store.account(automation.accountID)?.isReadyForAutomaticPublishing == true
        let showCloudButton = automation.deliveryMode == .automaticCloud
            || (automation.deliveryMode == .approval && canCloudPublish)

        if showCloudButton {
            Button {
                Task {
                    isPublishing = true
                    await store.submit(automation, publishNow: true)
                    isPublishing = false
                }
            } label: {
                Label(
                    isPublishing
                        ? "Publishing…"
                        : (automation.deliveryMode == .approval ? "Approve & Publish" : "Publish Now"),
                    systemImage: "cloud.fill"
                )
            }
            .buttonStyle(OrangeActionButtonStyle())
            .disabled(isPublishing)

            Button {
                startAssistedPublishing(automation)
            } label: {
                Label("Use Assisted Publishing", systemImage: "hand.tap.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                startAssistedPublishing(automation)
            } label: {
                Label(
                    automation.platform == .whatsapp
                        ? "Open WhatsApp / Share"
                        : "Open Share / Compose",
                    systemImage: "paperplane.fill"
                )
            }
            .buttonStyle(OrangeActionButtonStyle())
        }
    }

    private func secondaryButtons(_ automation: SocialAutomation) -> some View {
        HStack(spacing: 12) {
            Button {
                store.duplicate(automation)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            Button {
                store.pause(automation)
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.nextCard, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func historySection(_ automation: SocialAutomation) -> some View {
        if !automation.history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "History")
                ForEach(automation.history.reversed()) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.status.symbol)
                            .foregroundStyle(entry.status.color)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.status.title)
                                .font(.subheadline.bold())
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !entry.comment.isEmpty {
                                Text(entry.comment)
                                    .font(.subheadline)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .nextCard()
                }
            }
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.nextOrange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(14)
    }

    private func startAssistedPublishing(_ automation: SocialAutomation) {
        if let url = AssistedAutomationPublisher.url(automation), automation.media == nil {
            UIApplication.shared.open(url) { opened in
                if opened {
                    showCompletionConfirmation = true
                } else {
                    presentShareSheet(automation)
                }
            }
        } else {
            presentShareSheet(automation)
        }
    }

    private func presentShareSheet(_ automation: SocialAutomation) {
        shareItems = AssistedAutomationPublisher.items(
            automation,
            media: store.mediaData(automation)
        )
        if !shareItems.isEmpty {
            showShareSheet = true
        }
    }
}
