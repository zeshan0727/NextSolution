import SwiftUI

struct OnlineSearchView: View {
    var onOpenInBrowser: ((URL) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(onOpenInBrowser: ((URL) -> Void)? = nil) {
        self.onOpenInBrowser = onOpenInBrowser
    }

    @AppStorage("youtubeAPIKey") private var apiKey = ""
    @State private var query = ""
    @State private var results: [YouTubeVideo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedVideo: YouTubeVideo?
    @State private var directURL = ""
    @State private var directTitle = ""

    private let service = YouTubeService()

    var body: some View {
        NavigationView {
            List {
                Section("YouTube Search") {
                    HStack {
                        TextField("Search videos", text: $query)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onSubmit { Task { await search() } }
                        if isLoading { ProgressView() }
                    }
                    Button { Task { await search() } } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                    if apiKey.isEmpty {
                        Label("Add a YouTube Data API key in Settings to load official search results.", systemImage: "key.fill")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { video in
                            Button { selectedVideo = video } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: video.thumbnailURL) { phase in
                                        switch phase {
                                        case .success(let image): image.resizable().scaledToFill()
                                        default:
                                            ZStack {
                                                Color.secondary.opacity(0.12)
                                                Image(systemName: "play.rectangle.fill")
                                            }
                                        }
                                    }
                                    .frame(width: 118, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(video.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(3)
                                        Text(video.channelTitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Authorized Direct Download") {
                    TextField("Direct HTTPS media URL", text: $directURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    TextField("Optional title", text: $directTitle)
                    Button {
                        DownloadManager.shared.start(urlString: directURL, title: directTitle)
                        directURL = ""
                        directTitle = ""
                    } label: {
                        Label("Add to Downloads", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(directURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Use a direct media link you own or are authorized to download. YouTube search results open through YouTube's official player.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Online")
            .alert("Search Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .confirmationDialog(
                selectedVideo?.title ?? "Video",
                isPresented: Binding(
                    get: { selectedVideo != nil },
                    set: { if !$0 { selectedVideo = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let url = selectedVideo?.watchURL {
                    if let onOpenInBrowser {
                        Button("Open in Browser") {
                            selectedVideo = nil
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onOpenInBrowser(url)
                            }
                        }
                    } else {
                        Button("Play on YouTube") { UIApplication.shared.open(url) }
                    }
                }
                Button("Cancel", role: .cancel) { selectedVideo = nil }
            } message: {
                Text(onOpenInBrowser == nil ? "Open the result using YouTube." : "Open this result in the Next Media browser. Playback-aware media detection runs automatically.")
            }
        }
    }

    @MainActor
    private func search() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await service.search(query: clean, apiKey: apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
