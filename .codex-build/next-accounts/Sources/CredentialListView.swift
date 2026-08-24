import SwiftUI
import Foundation

private enum AccountSheet: Identifiable {
    case edit(Credential)
    case importEmails

    var id: String {
        switch self {
        case .edit(let credential): return "edit-\(credential.id.uuidString)"
        case .importEmails: return "import-emails"
        }
    }
}

struct CredentialListView: View {
    @EnvironmentObject private var store: CredentialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: AccountSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    AccountHeaderView(count: store.credentials.count)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(Array(store.credentials.enumerated()), id: \.element.id) { index, credential in
                        CredentialCard(
                            number: index + 1,
                            credential: credential,
                            onCopyEmail: {
                                store.copy(credential.email, label: "Email")
                            },
                            onCopyPassword: {
                                store.copy(credential.password, label: "Password")
                            },
                            onTogglePlatform: { platform in
                                store.toggle(platform, for: credential.id)
                            },
                            onEdit: {
                                presentedSheet = .edit(credential)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    GenerateMoreView(action: store.generateFive)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 30, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Next Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        presentedSheet = .importEmails
                    } label: {
                        Label("Import Emails", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import emails")
                }
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .edit(let credential):
                    EditCredentialSheet(credential: credential)
                case .importEmails:
                    ImportEmailsSheet()
                }
            }
            .overlay(alignment: .bottom) {
                if let message = store.statusMessage {
                    ToastView(message: message)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: store.statusMessage)
            .overlay {
                if scenePhase != .active {
                    PrivacyCoverView()
                }
            }
        }
    }
}

private struct AccountHeaderView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "envelope.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)

                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.gold)
                    .offset(x: 19, y: 19)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Account Copy Center")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(count) private account slots")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                Label("Passwords hidden by default", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct CredentialCard: View {
    let number: Int
    let credential: Credential
    let onCopyEmail: () -> Void
    let onCopyPassword: () -> Void
    let onTogglePlatform: (AccountPlatform) -> Void
    let onEdit: () -> Void

    @State private var showsPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Text(String(format: "%02d", number))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.14), in: Capsule())

                if credential.isGenerated {
                    Text("Local")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.gold.opacity(0.12), in: Capsule())
                }

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 36, height: 32)
                        .background(AppTheme.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit account")

                Button {
                    showsPassword.toggle()
                    HapticManager.shared.copied()
                } label: {
                    Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 36, height: 32)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
            }

            VStack(alignment: .leading, spacing: 9) {
                Label {
                    Text(credential.email.isEmpty ? "Tap pencil to add email" : credential.email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(credential.email.isEmpty ? Color.white.opacity(0.48) : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                } icon: {
                    Image(systemName: "envelope")
                        .foregroundStyle(AppTheme.accent)
                }

                Label {
                    Text(showsPassword ? credential.password : maskedPassword)
                        .font(.subheadline.monospaced().weight(.medium))
                        .foregroundStyle(showsPassword ? Color.white : Color.white.opacity(0.60))
                        .privacySensitive()
                } icon: {
                    Image(systemName: "key")
                        .foregroundStyle(AppTheme.gold)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AccountPlatform.allCases) { platform in
                        PlatformChip(
                            platform: platform,
                            isActive: credential.activePlatforms.contains(platform),
                            action: {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    onTogglePlatform(platform)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 10) {
                CopyButton(
                    title: "Copy Email",
                    systemImage: "doc.on.doc",
                    color: credential.email.isEmpty ? Color.gray : AppTheme.accent,
                    isDisabled: credential.email.isEmpty,
                    action: onCopyEmail
                )
                CopyButton(
                    title: "Copy Password",
                    systemImage: "key.fill",
                    color: AppTheme.gold,
                    action: onCopyPassword
                )
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
    }

    private var maskedPassword: String {
        String(repeating: "•", count: min(max(credential.password.count, 8), 14))
    }
}

private struct PlatformChip: View {
    let platform: AccountPlatform
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: platform.systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(platform.title)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.58))
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                isActive ? Color.green.opacity(0.88) : Color.white.opacity(0.065),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isActive ? Color.green.opacity(0.95) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(platform.title)
        .accessibilityValue(isActive ? "Selected" : "Not selected")
    }
}

private struct CopyButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1)
    }
}

private struct GenerateMoreView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            Button(action: action) {
                Label("Generate 5 More", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accent, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Text("Adds five empty private slots with passwords generated only on this iPhone.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
}

private struct EditCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CredentialStore

    let credential: Credential

    @State private var email: String
    @State private var password: String
    @State private var revealsPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    init(credential: Credential) {
        self.credential = credential
        _email = State(initialValue: credential.email)
        _password = State(initialValue: credential.password)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .focused($focusedField, equals: .email)

                    HStack {
                        Group {
                            if revealsPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)

                        Button {
                            revealsPassword.toggle()
                        } label: {
                            Image(systemName: revealsPassword ? "eye.slash.fill" : "eye.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                    }
                } footer: {
                    Text("Enter only an account you own. This information stays in this app's Keychain.")
                }

                Section {
                    Button {
                        password = store.freshPassword()
                        revealsPassword = true
                    } label: {
                        Label("Generate New Password", systemImage: "sparkles")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateCredential(id: credential.id, email: email, password: password)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                focusedField = credential.email.isEmpty ? .email : nil
            }
        }
    }

    private var canSave: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !password.isEmpty && (trimmedEmail.isEmpty || isValidEmail(trimmedEmail))
    }

    private func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !value.contains(" ")
    }
}

private struct ImportEmailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CredentialStore

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste Email Addresses") {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEditorFocused)
                } footer: {
                    Text("Use one address per line. Empty slots are filled first; extra addresses create new local slots.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Import Emails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let imported = store.importEmails(text)
                        if imported > 0 {
                            dismiss()
                        } else {
                            errorMessage = "No new valid email addresses were found."
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isEditorFocused = true
            }
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.78), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 14, y: 6)
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 13) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("Next Accounts")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Protected in the app switcher")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }
}
