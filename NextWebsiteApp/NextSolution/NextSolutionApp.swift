import SwiftUI

@main
struct NextSolutionApp: App {
    @StateObject private var videoService = VideoService()
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            NextSolutionRootView()
                .environmentObject(videoService)
                .environmentObject(downloadManager)
        }
    }
}
