import SwiftUI
import UIKit

struct DetectedMediaListView: View {
    @ObservedObject var session: BrowserSession
    let onDownload: (DetectedMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if session.detectedMedia.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text("No media detected yet")
                            .font(.headline)
                        Text("Play a video or audio item in the browser. Direct media links exposed by the page will appear here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                } else {
                    ForEach(session.detectedMedia) { media in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: media.kind.iconName)
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(media.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(media.hostText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    HStack(spacing: 7) {
                                        Text(media.formatText)
                                        if let quality = media.qualityText { Text("• \(quality)") }
                                        if media.wasPlaying { Text("• Playing") }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            HStack {
                                if media.canDownloadAsFile {
                                    Button { onDownload(media) } label: {
                                        Label("Download", systemImage: "arrow.down.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else if media.isPlaylist {
                                    Label("Streaming playlist", systemImage: "dot.radiowaves.left.and.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Label("Segmented media", systemImage: "square.stack.3d.down.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                                Button {
                                    UIPasteboard.general.url = media.url
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) { session.remove(media) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("Detected Media")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !session.detectedMedia.isEmpty {
                        Button("Clear") { session.clearDetectedMedia() }
                    }
                }
            }
        }
    }
}
