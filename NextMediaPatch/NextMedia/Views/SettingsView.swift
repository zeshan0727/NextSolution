import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("youtubeAPIKey") private var youtubeAPIKey = ""
    @AppStorage("autoMediaPrompt") private var autoMediaPrompt = true
    @AppStorage("browserHomeURL") private var browserHomeURL = "https://www.youtube.com"
    @State private var browsingDataCleared = false

    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Browser & Detection") {
                    TextField("Home page", text: $browserHomeURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    Toggle("Show download popup while media plays", isOn: $autoMediaPrompt)
                    Button(role: .destructive) {
                        BrowserDataManager.clearAll {
                            browsingDataCleared = true
                        }
                    } label: {
                        Label("Clear Browser Data", systemImage: "trash")
                    }
                    Text("The browser scans media elements and page resource requests for directly exposed video, audio and streaming-playlist URLs. Browser cookies, user agent and page referrer are carried into authorized file downloads.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Optional Native YouTube Search") {
                    SecureField("YouTube Data API key", text: $youtubeAPIKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("The API key is optional. Normal YouTube and web search works directly in the Browser tab without an API key. The key only powers the separate native thumbnail search screen.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Storage") {
                    HStack {
                        Text("Files")
                        Spacer()
                        Text("\(library.items.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Used")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: library.totalStorageBytes(), countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                }

                Section("Playback") {
                    Label("Background audio and lock-screen controls", systemImage: "lock.iphone")
                    Label("Picture in Picture for supported video", systemImage: "pip")
                    Label("AirPlay through the system player", systemImage: "airplayvideo")
                }

                Section("Media Download Compatibility") {
                    Text("Complete HTTP/HTTPS media files exposed directly by a page can be downloaded. Streaming playlists, short adaptive segments and DRM-protected playback are detected but are not falsely saved as complete videos.")
                        .font(.footnote)
                    Text("Use content you own or have permission to save. Availability depends on how each website delivers its media and may change when a site changes its player.")
                        .font(.footnote)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.1.0").foregroundColor(.secondary)
                    }
                    Text("Next Solution – Zeeshan 0727")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Browser Data Cleared", isPresented: $browsingDataCleared) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cookies, cache, local storage and browsing history data were removed from the in-app browser.")
            }
        }
    }
}
