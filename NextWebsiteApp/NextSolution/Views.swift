import SwiftUI

struct NextSolutionRootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack {
            HomeView(selectedTab: $selectedTab)
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)
            TutorialsView()
                .opacity(selectedTab == .tutorials ? 1 : 0)
                .allowsHitTesting(selectedTab == .tutorials)
            VideosView()
                .opacity(selectedTab == .videos ? 1 : 0)
                .allowsHitTesting(selectedTab == .videos)
            DownloadsView()
                .opacity(selectedTab == .downloads ? 1 : 0)
                .allowsHitTesting(selectedTab == .downloads)
            UploadsView()
                .opacity(selectedTab == .uploads ? 1 : 0)
                .allowsHitTesting(selectedTab == .uploads)
            FAQView()
                .opacity(selectedTab == .faq ? 1 : 0)
                .allowsHitTesting(selectedTab == .faq)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.purple : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @State private var sharePayload: SharedPayload?
    @Environment(\.openURL) private var openURL

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "Next Jailbreak",
                    subtitle: "Native iPhone customization hub",
                    trailingIcon: "square.and.arrow.up",
                    trailingAction: { sharePayload = SharedPayload(items: [AppData.websiteURL]) }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        hero
                        stats
                        quickActions
                        popularTutorials
                        benefits
                        community
                        disclaimer
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: payload.items)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Free step-by-step guides", systemImage: "shield.checkered")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.14), in: Capsule())

            Text("Unlock more from your iPhone.")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .minimumScaleFactor(0.75)

            Text("Clear jailbreak tutorials, rootless tweak guides, package conversion help and practical iOS customization videos.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.86))

            HStack(spacing: 10) {
                Button {
                    selectedTab = .tutorials
                } label: {
                    Label("Tutorials", systemImage: "book.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppTheme.purple)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white, in: Capsule())
                }

                Button {
                    selectedTab = .videos
                } label: {
                    Label("Videos", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
        }
        .foregroundColor(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 100, weight: .thin))
                .foregroundColor(.white.opacity(0.10))
                .padding(18)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            statCard(value: "Free", label: "Written guides")
            statCard(value: "83+", label: "Videos")
            statCard(value: "4.8K+", label: "Community")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundColor(AppTheme.purple)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "Everything in one place", subtitle: "Every section below is a native SwiftUI screen.")
            LazyVGrid(columns: columns, spacing: 12) {
                actionCard("Jailbreak Tutorials", "Structured instructions and troubleshooting.", "graduationcap.fill", .tutorials)
                actionCard("Rootless Tweaks", "Recommendations for modern jailbreaks.", "puzzlepiece.extension.fill", .tutorials)
                actionCard("Video Walkthroughs", "Latest uploads from your YouTube channel.", "play.rectangle.fill", .videos)
                actionCard("Direct Downloads", "Download packages and test apps natively.", "arrow.down.circle.fill", .downloads)
            }
        }
    }

    private func actionCard(_ title: String, _ detail: String, _ icon: String, _ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            NativeCard {
                VStack(alignment: .leading, spacing: 10) {
                    GradientIcon(systemName: icon)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var popularTutorials: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "Popular tutorials", subtitle: "Open full native summaries, requirements and steps.")
            ForEach(AppData.tutorials.prefix(3)) { tutorial in
                NavigationLink(destination: TutorialDetailView(tutorial: tutorial)) {
                    TutorialRow(tutorial: tutorial)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var benefits: some View {
        NativeCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: "What jailbreaking can offer", subtitle: "Compatibility varies by device and iOS version.")
                benefit("Install compatible tweaks beyond standard iOS options.")
                benefit("Customize themes, controls, gestures and system behaviour.")
                benefit("Explore deeper automation and productivity features.")
                benefit("Learn about packages, repositories and iOS system structure.")
            }
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.blue)
            Text(text)
                .font(.subheadline)
        }
    }

    private var community: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "Community", subtitle: "Open the official Next Jailbreak channels.")
            HStack(spacing: 10) {
                socialButton("YouTube", "play.fill", AppData.youtubeURL)
                socialButton("X", "bubble.left.and.bubble.right.fill", AppData.xURL)
                socialButton("Instagram", "camera.fill", AppData.instagramURL)
            }
        }
    }

    private func socialButton(_ title: String, _ icon: String, _ url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundColor(AppTheme.purple)
            .background(AppTheme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Educational use only. Back up important data, confirm exact compatibility and keep a recovery method available before changing system software.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct TutorialsView: View {
    @State private var searchText = ""
    @State private var sharePayload: SharedPayload?

    private var filtered: [Tutorial] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppData.tutorials
        }
        let query = searchText.lowercased()
        return AppData.tutorials.filter {
            $0.title.lowercased().contains(query)
                || $0.subtitle.lowercased().contains(query)
                || $0.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "Tutorials",
                    subtitle: "Native guides and troubleshooting",
                    trailingIcon: "square.and.arrow.up",
                    trailingAction: { sharePayload = SharedPayload(items: [URL(string: "https://nextjailbreak.com/tutorials.html")!]) }
                )

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search tutorials", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if let featured = filtered.first(where: \.featured) {
                            NavigationLink(destination: TutorialDetailView(tutorial: featured)) {
                                FeaturedTutorialCard(tutorial: featured)
                            }
                            .buttonStyle(.plain)
                        }

                        SectionTitle(title: "Written guides", subtitle: "Search by title, topic or compatibility tag.")

                        ForEach(filtered.filter { !$0.featured }) { tutorial in
                            NavigationLink(destination: TutorialDetailView(tutorial: tutorial)) {
                                TutorialRow(tutorial: tutorial)
                            }
                            .buttonStyle(.plain)
                        }

                        if filtered.isEmpty {
                            NativeCard {
                                VStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No tutorials found")
                                        .font(.headline)
                                    Text("Try another title, jailbreak name or iOS version.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $sharePayload) { ActivityView(items: $0.items) }
        }
        .navigationViewStyle(.stack)
    }
}

struct TutorialRow: View {
    let tutorial: Tutorial

    var body: some View {
        NativeCard {
            HStack(alignment: .top, spacing: 13) {
                GradientIcon(systemName: tutorial.icon)
                VStack(alignment: .leading, spacing: 7) {
                    Text(tutorial.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(tutorial.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tutorial.tags, id: \.self) { TagPill(text: $0) }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
        }
    }
}

struct FeaturedTutorialCard: View {
    let tutorial: Tutorial

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: tutorial.heroURL, height: 190, fallbackIcon: tutorial.icon)
            VStack(alignment: .leading, spacing: 10) {
                Label("Featured", systemImage: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme.blue)
                Text(tutorial.title)
                    .font(.title2.weight(.black))
                    .foregroundColor(.primary)
                Text(tutorial.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(tutorial.tags.prefix(4), id: \.self) { TagPill(text: $0) }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.purple.opacity(0.18), lineWidth: 1)
        )
    }
}

struct TutorialDetailView: View {
    let tutorial: Tutorial
    @State private var sharePayload: SharedPayload?
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openURL) private var openURL

    private var relatedDownloads: [DownloadItem] {
        AppData.downloads.filter { tutorial.relatedDownloadIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RemoteImage(url: tutorial.heroURL, height: tutorial.heroURL == nil ? 170 : 220, fallbackIcon: tutorial.icon)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(tutorial.title)
                        .font(.largeTitle.weight(.black))
                    Text(tutorial.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(tutorial.tags, id: \.self) { TagPill(text: $0) }
                        }
                    }
                }

                ForEach(tutorial.sections) { section in
                    NativeCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.title3.weight(.bold))
                            Text(section.body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.blue)
                                        .font(.subheadline)
                                        .padding(.top, 2)
                                    Text(bullet)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }

                if !relatedDownloads.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Downloads", subtitle: "Choose only the package matching your jailbreak.")
                        ForEach(relatedDownloads) { item in
                            DownloadCard(item: item)
                        }
                    }
                }

                Button {
                    openURL(tutorial.sourceURL)
                } label: {
                    PrimaryButtonLabel(title: "Open Full Source Guide", icon: "safari")
                }
                .buttonStyle(.plain)

                Button {
                    sharePayload = SharedPayload(items: [tutorial.title, tutorial.sourceURL])
                } label: {
                    Label("Share tutorial", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(AppTheme.purple)
                        .background(AppTheme.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .navigationTitle(tutorial.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { ActivityView(items: $0.items) }
        .sheet(item: $downloadManager.completedFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("Download", isPresented: Binding(
            get: { downloadManager.errorMessage != nil },
            set: { if !$0 { downloadManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { downloadManager.errorMessage = nil }
        } message: {
            Text(downloadManager.errorMessage ?? "")
        }
    }
}

struct VideosView: View {
    @EnvironmentObject private var videoService: VideoService
    @Environment(\.openURL) private var openURL
    @State private var sharePayload: SharedPayload?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "Videos",
                    subtitle: "Native YouTube channel feed",
                    trailingIcon: "arrow.clockwise",
                    trailingAction: { Task { await videoService.refresh() } }
                )

                ScrollView {
                    LazyVStack(spacing: 14) {
                        Button {
                            openURL(AppData.youtubeURL)
                        } label: {
                            PrimaryButtonLabel(title: "Open YouTube Channel", icon: "play.rectangle.fill")
                        }
                        .buttonStyle(.plain)

                        if videoService.isLoading && videoService.videos.isEmpty {
                            ProgressView("Loading latest videos…")
                                .padding(40)
                        }

                        if let error = videoService.errorMessage {
                            NativeCard {
                                VStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title)
                                        .foregroundColor(.orange)
                                    Text(error)
                                        .font(.subheadline)
                                        .multilineTextAlignment(.center)
                                    Button("Open YouTube") { openURL(AppData.youtubeURL) }
                                        .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        ForEach(videoService.videos) { video in
                            VideoCard(video: video)
                        }

                        if videoService.canLoadMore && !videoService.videos.isEmpty {
                            Button {
                                Task { await videoService.loadMore() }
                            } label: {
                                HStack {
                                    if videoService.isLoading { ProgressView() }
                                    Text(videoService.isLoading ? "Loading…" : "Load More Videos")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .disabled(videoService.isLoading)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await videoService.refresh()
                }
            }
            .navigationBarHidden(true)
            .task {
                await videoService.loadInitialIfNeeded()
            }
            .sheet(item: $sharePayload) { ActivityView(items: $0.items) }
        }
        .navigationViewStyle(.stack)
    }
}

struct VideoCard: View {
    let video: YouTubeVideo
    @Environment(\.openURL) private var openURL
    @State private var sharePayload: SharedPayload?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openURL(video.watchURL)
            } label: {
                ZStack {
                    RemoteImage(url: video.thumbnailURL, height: 190, fallbackIcon: "play.rectangle.fill")
                    Circle()
                        .fill(Color.black.opacity(0.62))
                        .frame(width: 58, height: 58)
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 9) {
                Text(video.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !video.description.isEmpty {
                    Text(video.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                HStack {
                    Text(Self.dateFormatter.string(from: video.publishedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        sharePayload = SharedPayload(items: [video.title, video.watchURL])
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button {
                        openURL(video.watchURL)
                    } label: {
                        Text("Watch")
                            .font(.caption.weight(.bold))
                    }
                }
            }
            .padding(15)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(item: $sharePayload) { ActivityView(items: $0.items) }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var selectedKind: DownloadItem.Kind?
    @Environment(\.openURL) private var openURL

    private var items: [DownloadItem] {
        guard let selectedKind else { return AppData.downloads }
        return AppData.downloads.filter { $0.kind == selectedKind }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "Downloads",
                    subtitle: "Native file downloads and package links",
                    trailingIcon: "shippingbox.fill",
                    trailingAction: { openURL(AppData.repoURL) }
                )

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                filterButton(title: "All", kind: nil)
                                ForEach(DownloadItem.Kind.allCases, id: \.self) { kind in
                                    filterButton(title: kind.rawValue, kind: kind)
                                }
                            }
                        }

                        if downloadManager.isDownloading, let item = downloadManager.activeItem {
                            NativeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Downloading")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(AppTheme.blue)
                                            Text(item.title)
                                                .font(.headline)
                                        }
                                        Spacer()
                                        Button("Cancel", action: downloadManager.cancel)
                                            .font(.caption.weight(.bold))
                                    }
                                    ProgressView(value: downloadManager.progress)
                                        .tint(AppTheme.blue)
                                    Text("\(Int(downloadManager.progress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        ForEach(items) { item in
                            DownloadCard(item: item)
                        }

                        NativeCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Installation note", systemImage: "exclamationmark.shield.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("Install only packages matching your jailbreak architecture. TIPA files require a compatible installer such as TrollStore; DEB packages require the correct jailbreak package manager.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $downloadManager.completedFile) { file in
                ActivityView(items: [file.url])
            }
            .alert("Download", isPresented: Binding(
                get: { downloadManager.errorMessage != nil },
                set: { if !$0 { downloadManager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { downloadManager.errorMessage = nil }
            } message: {
                Text(downloadManager.errorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func filterButton(title: String, kind: DownloadItem.Kind?) -> some View {
        Button {
            selectedKind = kind
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(selectedKind == kind ? .white : AppTheme.purple)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selectedKind == kind ? AnyShapeStyle(AppTheme.gradient) : AnyShapeStyle(AppTheme.purple.opacity(0.09)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DownloadCard: View {
    let item: DownloadItem
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        NativeCard {
            HStack(alignment: .top, spacing: 13) {
                GradientIcon(systemName: item.icon)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.title)
                            .font(.headline)
                        Spacer()
                        Text(item.version)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(AppTheme.blue)
                    }
                    Text(item.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        if item.externalOnly {
                            openURL(item.url)
                        } else {
                            downloadManager.download(item)
                        }
                    } label: {
                        Label(item.externalOnly ? "Open" : "Download", systemImage: item.externalOnly ? "arrow.up.right.square" : "arrow.down.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundColor(.white)
                            .background(AppTheme.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadManager.isDownloading && downloadManager.activeItem?.id != item.id)
                }
            }
        }
    }
}

struct UploadsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "Uploads",
                    subtitle: "Projects and source library",
                    trailingIcon: "arrow.up.right.square",
                    trailingAction: { openURL(AppData.githubURL) }
                )

                ScrollView {
                    LazyVStack(spacing: 14) {
                        NativeCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("GitHub-powered library", systemImage: "icloud.fill")
                                    .font(.headline)
                                    .foregroundColor(AppTheme.purple)
                                Text("Browse the source folders and published projects collected from your NextSolution GitHub repository. These buttons intentionally open GitHub because repository browsing and code editing belong outside the app.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        ForEach(AppData.uploads) { destination in
                            Button {
                                openURL(destination.url)
                            } label: {
                                NativeCard {
                                    HStack(spacing: 13) {
                                        GradientIcon(systemName: destination.icon)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(destination.title)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(destination.detail)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

struct FAQView: View {
    @State private var expandedID: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                NativeHeader(
                    title: "FAQ",
                    subtitle: "Safety, compatibility and app help",
                    trailingIcon: "envelope.fill",
                    trailingAction: { openURL(AppData.emailURL) }
                )

                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(AppData.faqItems) { item in
                            FAQCard(item: item, isExpanded: expandedID == item.id) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    expandedID = expandedID == item.id ? nil : item.id
                                }
                            }
                        }

                        NativeCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Still need help?")
                                    .font(.headline)
                                Text("Contact Next Jailbreak or open the official community channels.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 9) {
                                    Button("Email") { openURL(AppData.emailURL) }
                                        .buttonStyle(.borderedProminent)
                                    Button("YouTube") { openURL(AppData.youtubeURL) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

struct FAQCard: View {
    let item: FAQItem
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        NativeCard {
            Button(action: action) {
                VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.question)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: isExpanded ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(AppTheme.blue)
                    }
                    if isExpanded {
                        Text(item.answer)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
