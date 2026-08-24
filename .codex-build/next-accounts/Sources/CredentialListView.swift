import SwiftUI
import Foundation

struct CredentialListView: View {
    @EnvironmentObject private var store: CredentialStore
    @Environment(\.scenePhase) private var scenePhase

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
                Text("\(count) saved accounts")
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
                    Text("Generated")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.gold.opacity(0.12), in: Capsule())
                }

                Spacer()

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
                    Text(credential.email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
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

            HStack(spacing: 10) {
                CopyButton(
                    title: "Copy Email",
                    systemImage: "doc.on.doc",
                    color: AppTheme.accent,
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

private struct CopyButton: View {
    let title: String
    let systemImage: String
    let color: Color
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

            Text("Adds five address suggestions and passwords to this list. Gmail registration is separate.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
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
