import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VaultView: View {
    @EnvironmentObject private var vaultStore: VaultStore

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var sort: VaultSort = .recentlyUpdated
    @State private var favouritesOnly = false
    @State private var showingNewEntry = false
    @State private var editingEntry: VaultEntry?
    @State private var entryToDelete: VaultEntry?
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var filteredEntries: [VaultEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = vaultStore.entries.filter { entry in
            let searchMatches = query.isEmpty || entry.searchableText.contains(query)
            let categoryMatches = selectedCategory == "All"
                || entry.displayCategory.caseInsensitiveCompare(selectedCategory) == .orderedSame
            let favouriteMatches = !favouritesOnly || entry.isFavourite
            return searchMatches && categoryMatches && favouriteMatches
        }
        switch sort {
        case .recentlyUpdated:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .recentlyAdded:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .serviceAZ:
            return filtered.sorted { $0.service.localizedCaseInsensitiveCompare($1.service) == .orderedAscending }
        case .category:
            return filtered.sorted {
                if $0.displayCategory == $1.displayCategory {
                    return $0.service.localizedCaseInsensitiveCompare($1.service) == .orderedAscending
                }
                return $0.displayCategory.localizedCaseInsensitiveCompare($1.displayCategory) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        vaultHeader
                        categoryStrip

                        if filteredEntries.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredEntries) { entry in
                                    NavigationLink {
                                        VaultDetailView(entryID: entry.id)
                                            .environmentObject(vaultStore)
                                    } label: {
                                        VaultEntryCard(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            vaultStore.toggleFavourite(entryID: entry.id)
                                        } label: {
                                            Label(
                                                entry.isFavourite ? "Remove Favourite" : "Add Favourite",
                                                systemImage: entry.isFavourite ? "star.slash" : "star"
                                            )
                                        }
                                        Button {
                                            UIPasteboard.general.string = entry.userID
                                            showNotice("Login Copied", "The user ID or login email was copied.")
                                        } label: {
                                            Label("Copy Login", systemImage: "person.crop.circle.badge.checkmark")
                                        }
                                        Button {
                                            copyPassword(entry)
                                        } label: {
                                            Label("Copy Password", systemImage: "key.fill")
                                        }
                                        Button {
                                            requestEdit(entry)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Logins")
            .searchable(text: $searchText, prompt: "Search service, website, login or notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(VaultSort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        Toggle("Favourites Only", isOn: $favouritesOnly)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add Login")
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                VaultEditorView()
                    .environmentObject(vaultStore)
            }
            .sheet(item: $editingEntry) { entry in
                VaultEditorView(entry: entry)
                    .environmentObject(vaultStore)
            }
            .confirmationDialog(
                "Delete this login?",
                isPresented: Binding(
                    get: { entryToDelete != nil },
                    set: { if !$0 { entryToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Login and Attachments", role: .destructive) {
                    if let entryToDelete { vaultStore.delete(entryToDelete) }
                    entryToDelete = nil
                }
                Button("Cancel", role: .cancel) { entryToDelete = nil }
            } message: {
                Text("This permanently removes the login, its Keychain password and saved attachments.")
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(noticeMessage)
            }
            .alert("Secure Logins Error", isPresented: Binding(
                get: { vaultStore.lastError != nil },
                set: { if !$0 { vaultStore.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { vaultStore.lastError = nil }
            } message: {
                Text(vaultStore.lastError ?? "Unknown error")
            }
        }
    }

    private var vaultHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Secure Login Vault")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Passwords are protected by Keychain and device authentication.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                }
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
            }

            HStack(spacing: 12) {
                headerMetric(title: "Logins", value: "\(vaultStore.entries.count)", icon: "key.fill")
                headerMetric(title: "Categories", value: "\(vaultStore.categories.count)", icon: "folder.fill")
                headerMetric(
                    title: "Favourites",
                    value: "\(vaultStore.entries.filter(\.isFavourite).count)",
                    icon: "star.fill"
                )
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.blue, Color.cyan.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.indigo.opacity(0.22), radius: 18, y: 9)
    }

    private func headerMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton("All")
                ForEach(vaultStore.sortedCategories, id: \.self) { category in
                    categoryButton(category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryButton(_ category: String) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(category)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                .background(
                    selectedCategory == category ? Color.indigo : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: vaultStore.entries.isEmpty ? "key.horizontal.fill" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.indigo)
            Text(vaultStore.entries.isEmpty ? "No logins saved" : "No matching logins")
                .font(.title3.bold())
            Text(vaultStore.entries.isEmpty
                 ? "Tap + to save your first service, website, login and password."
                 : "Change your search, category or favourite filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .glassCard()
    }

    private func requestEdit(_ entry: VaultEntry) {
        Task {
            if await VaultSecurity.authenticate(reason: "Authenticate to edit this saved login.") {
                editingEntry = entry
            } else {
                showNotice("Authentication Required", "The login was not opened for editing.")
            }
        }
    }

    private func copyPassword(_ entry: VaultEntry) {
        Task {
            guard await VaultSecurity.authenticate(reason: "Authenticate to copy the password for \(entry.service).") else {
                showNotice("Authentication Required", "The password was not copied.")
                return
            }
            let password = vaultStore.password(for: entry.id)
            guard !password.isEmpty else {
                showNotice("Password Missing", "No Keychain password is available for this login.")
                return
            }
            UIPasteboard.general.string = password
            showNotice("Password Copied", "The password was copied to the clipboard.")
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}

private struct VaultEntryCard: View {
    let entry: VaultEntry

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.95), Color.blue.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(entry.initial.isEmpty ? "?" : entry.initial)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.service)
                        .font(.headline)
                        .lineLimit(1)
                    if entry.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(entry.userID.isEmpty ? "No login ID" : entry.userID)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Label(entry.displayCategory, systemImage: "folder.fill")
                    if !entry.attachments.isEmpty {
                        Label("\(entry.attachments.count)", systemImage: "paperclip")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.indigo)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct VaultDetailView: View {
    @EnvironmentObject private var vaultStore: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let entryID: UUID

    @State private var revealedPassword = ""
    @State private var isPasswordVisible = false
    @State private var showingEditor = false
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var showingDelete = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var entry: VaultEntry? { vaultStore.entry(id: entryID) }

    var body: some View {
        ZStack {
            AppBackground()
            if let entry {
                ScrollView {
                    VStack(spacing: 16) {
                        identityCard(entry)
                        passwordCard(entry)
                        informationCard(entry)
                        attachmentsCard(entry)
                        dangerCard(entry)
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Login not found").font(.title3.bold())
                }
            }
        }
        .navigationTitle(entry?.service ?? "Login")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        vaultStore.toggleFavourite(entryID: entry.id)
                    } label: {
                        Image(systemName: entry.isFavourite ? "star.fill" : "star")
                    }
                    Button("Edit") { authenticateForEditing(entry) }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let entry {
                VaultEditorView(entry: entry)
                    .environmentObject(vaultStore)
            }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL { VaultQuickLookView(url: previewURL) }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { VaultActivityView(items: [shareURL]) }
        }
        .confirmationDialog("Delete this login?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete Login and Attachments", role: .destructive) {
                if let entry { vaultStore.delete(entry) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Keychain password and all saved attachments will be permanently removed.")
        }
        .alert(noticeTitle, isPresented: $showingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                isPasswordVisible = false
                revealedPassword = ""
            }
        }
    }

    private func identityCard(_ entry: VaultEntry) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(entry.initial.isEmpty ? "?" : entry.initial)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.service)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Label(entry.displayCategory, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text("Added \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private func passwordCard(_ entry: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: "Password", systemImage: "key.fill")
            HStack(spacing: 10) {
                Text(isPasswordVisible ? revealedPassword : "••••••••••••••••")
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer()
                Button {
                    togglePassword(entry)
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                }
                Button {
                    copyPassword(entry)
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                }
            }
            Text("Face ID or the device passcode is required to reveal or copy this password.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func informationCard(_ entry: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Login Information", systemImage: "person.text.rectangle.fill")
            detailRow("Login / User ID", value: entry.userID.isEmpty ? "Not entered" : entry.userID) {
                if !entry.userID.isEmpty {
                    UIPasteboard.general.string = entry.userID
                    showNotice("Login Copied", "The login ID was copied.")
                }
            }
            detailRow("Website", value: entry.website.isEmpty ? "Not entered" : entry.website) {
                if let url = entry.websiteURL { openURL(url) }
            }
            detailRow("Category", value: entry.displayCategory, action: nil)
            detailRow("Last updated", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened), action: nil)
            if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.notes)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
        .glassCard()
    }

    private func detailRow(_ title: String, value: String, action: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).textSelection(.enabled)
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: title == "Website" ? "arrow.up.right.square" : "doc.on.doc")
                }
            }
        }
    }

    private func attachmentsCard(_ entry: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionTitle(title: "Attachments", systemImage: "paperclip")
            if entry.attachments.isEmpty {
                Text("No screenshots, photos or files are attached.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.attachments) { attachment in
                    HStack(spacing: 11) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.originalName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("\(attachment.formattedSize) • \(attachment.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button {
                                previewURL = vaultStore.attachmentURL(attachment, entryID: entry.id)
                            } label: {
                                Label("Preview", systemImage: "eye")
                            }
                            Button {
                                shareURL = vaultStore.attachmentURL(attachment, entryID: entry.id)
                            } label: {
                                Label("Share / Save", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .glassCard()
    }

    private func dangerCard(_ entry: VaultEntry) -> some View {
        Button(role: .destructive) {
            showingDelete = true
        } label: {
            Label("Delete Login", systemImage: "trash.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .glassCard()
    }

    private func authenticateForEditing(_ entry: VaultEntry) {
        Task {
            if await VaultSecurity.authenticate(reason: "Authenticate to edit \(entry.service).") {
                showingEditor = true
            } else {
                showNotice("Authentication Required", "The login was not opened for editing.")
            }
        }
    }

    private func togglePassword(_ entry: VaultEntry) {
        if isPasswordVisible {
            isPasswordVisible = false
            revealedPassword = ""
            return
        }
        Task {
            guard await VaultSecurity.authenticate(reason: "Authenticate to reveal the password for \(entry.service).") else {
                showNotice("Authentication Required", "The password remains hidden.")
                return
            }
            let value = vaultStore.password(for: entry.id)
            guard !value.isEmpty else {
                showNotice("Password Missing", "No Keychain password is available for this login.")
                return
            }
            revealedPassword = value
            isPasswordVisible = true
        }
    }

    private func copyPassword(_ entry: VaultEntry) {
        Task {
            guard await VaultSecurity.authenticate(reason: "Authenticate to copy the password for \(entry.service).") else {
                showNotice("Authentication Required", "The password was not copied.")
                return
            }
            let value = vaultStore.password(for: entry.id)
            guard !value.isEmpty else {
                showNotice("Password Missing", "No Keychain password is available for this login.")
                return
            }
            UIPasteboard.general.string = value
            showNotice("Password Copied", "The password was copied to the clipboard.")
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}

struct VaultEditorView: View {
    @EnvironmentObject private var vaultStore: VaultStore
    @Environment(\.dismiss) private var dismiss

    private let originalEntry: VaultEntry?

    @State private var draft: VaultEntry
    @State private var password = ""
    @State private var showingPassword = false
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var previewURL: URL?
    @State private var isImporting = false
    @State private var addedAttachmentIDs: Set<UUID> = []
    @State private var removedOriginalAttachments: [VaultAttachment] = []
    @State private var didSave = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    init(entry: VaultEntry? = nil) {
        originalEntry = entry
        _draft = State(initialValue: entry ?? VaultEntry())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Account") {
                        TextField("Service", text: $draft.service)
                            .textInputAutocapitalization(.words)
                        TextField("Website", text: $draft.website)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("User ID or login email", text: $draft.userID)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Section("Password") {
                        HStack {
                            Group {
                                if showingPassword {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.newPassword)

                            Button {
                                showingPassword.toggle()
                            } label: {
                                Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                            }
                        }
                        Button {
                            password = VaultPasswordGenerator.generate()
                            showingPassword = true
                        } label: {
                            Label("Generate Strong Password", systemImage: "wand.and.stars")
                        }
                    }

                    Section("Category") {
                        TextField("Category", text: $draft.category)
                            .textInputAutocapitalization(.words)
                        if !vaultStore.sortedCategories.isEmpty {
                            Menu {
                                ForEach(vaultStore.sortedCategories, id: \.self) { category in
                                    Button(category) { draft.category = category }
                                }
                            } label: {
                                Label("Choose Existing Category", systemImage: "folder")
                            }
                        }
                        Text("A new category is created automatically when this login is saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Attachments") {
                        Menu {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera.fill")
                            }
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                            Button {
                                showingPhotos = true
                            } label: {
                                Label("Photos or Screenshots", systemImage: "photo.on.rectangle.angled")
                            }

                            Button {
                                showingFiles = true
                            } label: {
                                Label("Files", systemImage: "folder.fill")
                            }
                        } label: {
                            Label("Add Attachment", systemImage: "paperclip.circle.fill")
                        }

                        if draft.attachments.isEmpty {
                            Text("Attach screenshots, camera photos, gallery images, PDFs or other individual files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(draft.attachments) { attachment in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.fill").foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.originalName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(attachment.formattedSize)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        previewURL = vaultStore.attachmentURL(attachment, entryID: draft.id)
                                    } label: {
                                        Image(systemName: "eye")
                                    }
                                    Button(role: .destructive) {
                                        removeAttachment(attachment)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Section("Notes") {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 110)
                    }

                    Section("Record Information") {
                        LabeledContent("Date added", value: draft.createdAt.formatted(date: .long, time: .shortened))
                        if originalEntry != nil {
                            LabeledContent("Last updated", value: draft.updatedAt.formatted(date: .long, time: .shortened))
                        }
                        Toggle("Favourite", isOn: $draft.isFavourite)
                    }

                    Section {
                        Text("Passwords are stored in the iPhone Keychain and are not written into the normal Next Job database or plaintext backup files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isImporting {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Protecting and importing attachments…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationTitle(originalEntry == nil ? "New Login" : "Edit Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isImporting)
                }
            }
            .onAppear {
                if let originalEntry, password.isEmpty {
                    password = vaultStore.password(for: originalEntry.id)
                }
            }
            .onDisappear {
                if !didSave { cleanupUnsavedAttachments() }
            }
            .sheet(isPresented: $showingCamera) {
                VaultCameraPicker { image in
                    showingCamera = false
                    guard let image else { return }
                    do {
                        let name = "Camera-\(Self.attachmentDateFormatter.string(from: Date())).jpg"
                        let attachment = try vaultStore.addImage(image, entryID: draft.id, suggestedName: name)
                        draft.attachments.append(attachment)
                        addedAttachmentIDs.insert(attachment.id)
                    } catch {
                        showNotice("Camera Photo Not Added", error.localizedDescription)
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showingPhotos,
                selection: $selectedPhotoItems,
                maxSelectionCount: 20,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { items in
                importPhotos(items)
            }
            .fileImporter(
                isPresented: $showingFiles,
                allowedContentTypes: [.data, .image, .pdf, .text],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
            .sheet(isPresented: Binding(
                get: { previewURL != nil },
                set: { if !$0 { previewURL = nil } }
            )) {
                if let previewURL { VaultQuickLookView(url: previewURL) }
            }
            .alert(noticeTitle, isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(noticeMessage)
            }
        }
    }

    private func save() {
        do {
            try vaultStore.save(draft, password: password)
            for attachment in removedOriginalAttachments {
                vaultStore.deleteAttachmentFile(attachment, entryID: draft.id)
            }
            didSave = true
            dismiss()
        } catch {
            showNotice("Login Not Saved", error.localizedDescription)
        }
    }

    private func cancelAndDismiss() {
        cleanupUnsavedAttachments()
        didSave = true
        dismiss()
    }

    private func removeAttachment(_ attachment: VaultAttachment) {
        draft.attachments.removeAll { $0.id == attachment.id }
        if addedAttachmentIDs.contains(attachment.id) {
            vaultStore.deleteAttachmentFile(attachment, entryID: draft.id)
            addedAttachmentIDs.remove(attachment.id)
        } else if originalEntry?.attachments.contains(where: { $0.id == attachment.id }) == true {
            removedOriginalAttachments.append(attachment)
        }
    }

    private func cleanupUnsavedAttachments() {
        if originalEntry == nil {
            vaultStore.cleanupDraft(entryID: draft.id)
        } else {
            for attachment in draft.attachments where addedAttachmentIDs.contains(attachment.id) {
                vaultStore.deleteAttachmentFile(attachment, entryID: draft.id)
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isImporting = true
            defer { isImporting = false }
            for url in urls {
                let attachment = try vaultStore.addFile(from: url, entryID: draft.id)
                draft.attachments.append(attachment)
                addedAttachmentIDs.insert(attachment.id)
            }
        } catch {
            isImporting = false
            showNotice("Files Not Added", error.localizedDescription)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            defer {
                isImporting = false
                selectedPhotoItems = []
            }
            for (index, item) in items.enumerated() {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        throw VaultError.imageCouldNotBeSaved
                    }
                    let name = "Photo-\(Self.attachmentDateFormatter.string(from: Date()))-\(index + 1).jpg"
                    let attachment = try vaultStore.addData(jpeg, entryID: draft.id, originalName: name)
                    draft.attachments.append(attachment)
                    addedAttachmentIDs.insert(attachment.id)
                } catch {
                    showNotice("Photo Not Added", error.localizedDescription)
                }
            }
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }

    private static let attachmentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

struct VaultCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

struct VaultQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct VaultActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
