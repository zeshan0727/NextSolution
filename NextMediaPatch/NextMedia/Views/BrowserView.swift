import SwiftUI
import UIKit

struct BrowserView: View {
    @StateObject private var session = BrowserSession()
    @State private var showDetectedMedia = false
    @State private var showYouTubeSearch = false
    @State private var isPreparingDownload = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                addressBar

                if session.isLoading {
                    ProgressView(value: max(0.03, session.estimatedProgress))
                        .progressViewStyle(.linear)
                }

                BrowserWebView(session: session)
                    .overlay(alignment: .bottomTrailing) {
                        if !session.detectedMedia.isEmpty {
                            Button { showDetectedMedia = true } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("\(session.detectedMedia.count)")
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(.ultraThinMaterial, in: Capsule())
                                .shadow(radius: 8, y: 3)
                            }
                            .padding(14)
                            .accessibilityLabel("Show detected media")
                        }
                    }

                browserToolbar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(session.pageTitle).font(.headline).lineLimit(1)
                        Text(session.currentURL?.host ?? "Private in-app browser")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showYouTubeSearch = true } label: {
                        Image(systemName: "play.rectangle.on.rectangle")
                    }
                    .accessibilityLabel("Native YouTube search")
                }
            }
            .sheet(isPresented: $showDetectedMedia) {
                DetectedMediaListView(session: session, onDownload: startDownload)
            }
            .sheet(isPresented: $showYouTubeSearch) {
                OnlineSearchView { url in
                    session.load(url)
                }
            }
            .confirmationDialog(
                session.promptedMedia?.title ?? "Media detected",
                isPresented: Binding(
                    get: { session.promptedMedia != nil },
                    set: { if !$0 { session.promptedMedia = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let media = session.promptedMedia, media.canDownloadAsFile {
                    Button(isPreparingDownload ? "Preparing…" : "Download \(media.formatText)") {
                        startDownload(media)
                    }
                    .disabled(isPreparingDownload)
                }
                if session.promptedMedia?.isPlaylist == true {
                    Button("View Stream Details") { showDetectedMedia = true }
                }
                Button("Show All Detected Media") { showDetectedMedia = true }
                if let media = session.promptedMedia {
                    Button("Copy Media URL") { UIPasteboard.general.url = media.url }
                }
                Button("Cancel", role: .cancel) { session.promptedMedia = nil }
            } message: {
                if let media = session.promptedMedia {
                    Text(media.canDownloadAsFile
                         ? "A directly exposed \(media.kind.title.lowercased()) file was detected while playback was active."
                         : "The page exposed a streaming playlist or segment rather than one complete downloadable file.")
                }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: session.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Search YouTube or enter website", text: $session.addressText)
                .textInputAutocapitalization(.never)
                .keyboardType(.webSearch)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .onSubmit { session.submitAddress() }
            if !session.addressText.isEmpty {
                Button { session.addressText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
            Button { session.submitAddress() } label: {
                Image(systemName: "arrow.right.circle.fill").font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var browserToolbar: some View {
        HStack {
            Button { session.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!session.canGoBack)
            Spacer()
            Button { session.goForward() } label: { Image(systemName: "chevron.forward") }
                .disabled(!session.canGoForward)
            Spacer()
            Button { session.reloadOrStop() } label: {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
            }
            Spacer()
            Button { session.loadHome() } label: { Image(systemName: "house.fill") }
            Spacer()
            Button { showDetectedMedia = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                    if !session.detectedMedia.isEmpty {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 3, y: -2)
                    }
                }
            }
        }
        .font(.title3)
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
    }

    private func startDownload(_ media: DetectedMedia) {
        guard media.canDownloadAsFile else {
            showDetectedMedia = true
            session.promptedMedia = nil
            return
        }
        isPreparingDownload = true
        Task {
            let headers = await session.downloadHeaders(for: media)
            DownloadManager.shared.start(
                urlString: media.url.absoluteString,
                title: media.title,
                headers: headers
            )
            await MainActor.run {
                isPreparingDownload = false
                session.promptedMedia = nil
            }
        }
    }
}
