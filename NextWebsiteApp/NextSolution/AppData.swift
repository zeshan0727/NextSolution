import Foundation

enum AppData {
    static let websiteURL = URL(string: "https://nextjailbreak.com/")!
    static let youtubeURL = URL(string: "https://youtube.com/@nextjailbreak")!
    static let xURL = URL(string: "https://x.com/nextjailbreak")!
    static let instagramURL = URL(string: "https://instagram.com/nextjailbreak")!
    static let emailURL = URL(string: "mailto:NextSolution@zeshanbarvi.uk")!
    static let githubURL = URL(string: "https://github.com/zeshan0727/NextSolution")!
    static let repoURL = URL(string: "https://nextjailbreak.com/")!
    static let sileoURL = URL(string: "sileo://source/https://nextjailbreak.com/")!

    static let tutorials: [Tutorial] = [
        Tutorial(
            id: "phoneaura",
            title: "PhoneAura 0.4.15",
            subtitle: "A complete native Phone app redesign for iOS 16 jailbreaks.",
            icon: "phone.fill",
            tags: ["iOS 16+", "RootHide", "Rootless", "Free"],
            heroURL: nil,
            sourceURL: URL(string: "https://nextjailbreak.com/phoneaura-tweak-ios16.html")!,
            featured: true,
            sections: [
                TutorialSection(
                    title: "What PhoneAura changes",
                    body: "PhoneAura replaces the main Phone app surfaces with a modern card-based interface while keeping the important calling actions close to the original iOS behaviour.",
                    bullets: [
                        "Custom Favorites with large contact cards and quick actions.",
                        "Smart Recents filters for all, dialed, received and missed calls.",
                        "Redesigned Contacts with search and profile cards.",
                        "A fixed-height smart keypad that does not jump while suggestions update.",
                        "Native long-press Cut, Copy and Paste controls where safe."
                    ]
                ),
                TutorialSection(
                    title: "Choose the correct package",
                    body: "RootHide and standard rootless jailbreaks use different package architectures. Install only one variant.",
                    bullets: [
                        "RootHide users: install the iphoneos-arm64e package.",
                        "Standard rootless users: install the iphoneos-arm64 package.",
                        "Do not install both variants because they use the same package identifier."
                    ]
                ),
                TutorialSection(
                    title: "Installation",
                    body: "Add the Next Jailbreak repository in Sileo, search for PhoneAura, confirm version 0.4.15 and the correct architecture, install, then respring.",
                    bullets: [
                        "Fully close the Phone app after respring.",
                        "Open Settings → PhoneAura and choose the replacement tabs.",
                        "Test Keypad suggestions, long-press editing, Recents filters and Favorites."
                    ]
                )
            ],
            relatedDownloadIDs: ["phoneaura-roothide", "phoneaura-rootless"]
        ),
        Tutorial(
            id: "rootful-rootless",
            title: "Convert Rootful Tweaks to Rootless",
            subtitle: "Prepare older packages for Dopamine 2, XinaA15 and palera1n.",
            icon: "arrow.triangle.2.circlepath",
            tags: ["Conversion", "Dopamine 2", "palera1n"],
            heroURL: nil,
            sourceURL: URL(string: "https://nextjailbreak.com/convert-rootful-to-rootless.html")!,
            featured: false,
            sections: [
                TutorialSection(
                    title: "Before conversion",
                    body: "Confirm that the original package is compatible with your iOS version and inspect its filesystem paths, dependencies and injected binaries.",
                    bullets: [
                        "Back up the original DEB before changing it.",
                        "Check whether dependencies already have rootless builds.",
                        "Do not assume every rootful tweak can be converted safely."
                    ]
                ),
                TutorialSection(
                    title: "Core conversion checks",
                    body: "Rootless packages normally move jailbreak files under the rootless prefix and require correctly patched binaries and package scripts.",
                    bullets: [
                        "Update filesystem paths and maintainer scripts.",
                        "Patch Mach-O binaries and libraries for the target environment.",
                        "Rebuild the package, install in a safe test environment and review crash logs."
                    ]
                )
            ],
            relatedDownloadIDs: []
        ),
        Tutorial(
            id: "rootless-tweaks",
            title: "25+ Free iOS 16 Rootless Tweaks",
            subtitle: "A curated collection of useful free tweaks and repositories.",
            icon: "puzzlepiece.extension.fill",
            tags: ["Free", "iOS 16", "Tweaks"],
            heroURL: nil,
            sourceURL: URL(string: "https://nextjailbreak.com/ios16-rootless-tweaks.html")!,
            featured: false,
            sections: [
                TutorialSection(
                    title: "Compatibility first",
                    body: "A tweak must support your exact iOS version, jailbreak type and device architecture. Rootless compatibility is separate from general iOS compatibility.",
                    bullets: [
                        "Read the package depiction and changelog.",
                        "Install one system-level tweak at a time.",
                        "Keep safe mode available before testing interface modifications."
                    ]
                ),
                TutorialSection(
                    title: "Installation approach",
                    body: "Add only trusted repositories, refresh package sources and confirm dependencies before installing.",
                    bullets: [
                        "Avoid duplicate packages from unknown repositories.",
                        "Respring only after the package manager finishes.",
                        "Remove the newest tweak first if instability begins."
                    ]
                )
            ],
            relatedDownloadIDs: []
        ),
        Tutorial(
            id: "ios16-jailbreak",
            title: "Complete iOS 16 Jailbreak Guide",
            subtitle: "Requirements, palera1n workflow and common troubleshooting.",
            icon: "lock.open.fill",
            tags: ["iOS 16", "palera1n", "Guide"],
            heroURL: nil,
            sourceURL: URL(string: "https://nextjailbreak.com/how-to-jailbreak.html")!,
            featured: false,
            sections: [
                TutorialSection(
                    title: "Confirm support",
                    body: "Jailbreak support depends on the exact device chipset and iOS build. Confirm compatibility before downloading tools or changing the device.",
                    bullets: [
                        "Create an encrypted Finder or iTunes backup.",
                        "Record the device model and exact iOS version.",
                        "Use the official project source for the jailbreak tool."
                    ]
                ),
                TutorialSection(
                    title: "After installation",
                    body: "Install only compatible packages and keep a recovery path available.",
                    bullets: [
                        "Test the package manager before adding third-party sources.",
                        "Learn how to enter safe mode and remove a problematic tweak.",
                        "Do not update iOS until you confirm the impact on jailbreak compatibility."
                    ]
                )
            ],
            relatedDownloadIDs: []
        ),
        Tutorial(
            id: "battery-service",
            title: "Remove the Battery Service Message",
            subtitle: "Understand the 3uTools battery-health information process.",
            icon: "battery.50",
            tags: ["Battery", "3uTools", "Guide"],
            heroURL: nil,
            sourceURL: URL(string: "https://nextjailbreak.com/remove-service-message-iphone.html")!,
            featured: false,
            sections: [
                TutorialSection(
                    title: "Important warning",
                    body: "Battery health information and actual battery condition are not the same thing. Removing a warning does not repair a worn or unsafe battery.",
                    bullets: [
                        "Replace swollen, overheating or damaged batteries immediately.",
                        "Keep a full backup before modifying battery data.",
                        "Use a qualified repair provider when physical battery work is required."
                    ]
                ),
                TutorialSection(
                    title: "Verify the result",
                    body: "After completing the procedure, restart the device and compare Settings battery information with real-world charging, temperature and runtime behaviour.",
                    bullets: []
                )
            ],
            relatedDownloadIDs: []
        )
    ]

    static let downloads: [DownloadItem] = [
        DownloadItem(
            id: "module-glass-preview",
            title: "Module Glass Preview",
            detail: "Live companion for previewing and changing Module Glass Control Center backgrounds on a TrollStore device.",
            version: "1.0.0",
            kind: .app,
            icon: "square.grid.2x2.fill",
            url: URL(string: "https://raw.githubusercontent.com/zeshan0727/NextSolution/main/NextWebsiteApp/downloads/ModuleGlass-Preview-1.0.0.tipa")!,
            fileName: "ModuleGlass-Preview-1.0.0.tipa",
            externalOnly: false
        ),
        DownloadItem(
            id: "phoneaura-roothide",
            title: "PhoneAura RootHide",
            detail: "RootHide build for iphoneos-arm64e devices.",
            version: "0.4.15",
            kind: .package,
            icon: "phone.fill",
            url: URL(string: "https://nextjailbreak.com/debfiles/PhoneAura_0.4.15_RootHide_iOS16.deb")!,
            fileName: "PhoneAura_0.4.15_RootHide_iOS16.deb",
            externalOnly: false
        ),
        DownloadItem(
            id: "phoneaura-rootless",
            title: "PhoneAura Rootless",
            detail: "Standard rootless build for iphoneos-arm64.",
            version: "0.4.15",
            kind: .package,
            icon: "phone.fill",
            url: URL(string: "https://nextjailbreak.com/debfiles/PhoneAura_0.4.15_Rootless_iOS16.deb")!,
            fileName: "PhoneAura_0.4.15_Rootless_iOS16.deb",
            externalOnly: false
        ),
        DownloadItem(
            id: "nextpdf",
            title: "NextPDF TIPA",
            detail: "Latest repository build of the NextPDF editor for TrollStore testing.",
            version: "Latest",
            kind: .app,
            icon: "doc.richtext.fill",
            url: URL(string: "https://raw.githubusercontent.com/zeshan0727/NextSolution/main/NextPDF/build-output/NextPDF.tipa")!,
            fileName: "NextPDF.tipa",
            externalOnly: false
        ),
        DownloadItem(
            id: "source-archive",
            title: "NextSolution Source Archive",
            detail: "Download the current public GitHub repository as a ZIP file.",
            version: "main",
            kind: .source,
            icon: "chevron.left.forwardslash.chevron.right",
            url: URL(string: "https://github.com/zeshan0727/NextSolution/archive/refs/heads/main.zip")!,
            fileName: "NextSolution-main.zip",
            externalOnly: false
        ),
        DownloadItem(
            id: "sileo-repo",
            title: "Add Next Jailbreak Repository",
            detail: "Open the official package source directly in Sileo.",
            version: "Official",
            kind: .repository,
            icon: "shippingbox.fill",
            url: sileoURL,
            fileName: nil,
            externalOnly: true
        )
    ]

    static let uploads: [UploadDestination] = [
        UploadDestination(
            id: "repo",
            title: "NextSolution Repository",
            detail: "Browse all public projects, website files and source code.",
            icon: "chevron.left.forwardslash.chevron.right",
            url: githubURL
        ),
        UploadDestination(
            id: "daily-tweaks",
            title: "Daily Tweaks",
            detail: "Open the collection of jailbreak tweak projects and build files.",
            icon: "wand.and.stars",
            url: URL(string: "https://github.com/zeshan0727/NextSolution/tree/main/DailyTweaks")!
        ),
        UploadDestination(
            id: "nextpdf-source",
            title: "NextPDF Project",
            detail: "View the Swift source, build workflow and published test output.",
            icon: "doc.text.magnifyingglass",
            url: URL(string: "https://github.com/zeshan0727/NextSolution/tree/main/NextPDF")!
        ),
        UploadDestination(
            id: "ledger-source",
            title: "Next Ledger Project",
            detail: "Browse the native personal-finance app source and services.",
            icon: "chart.pie.fill",
            url: URL(string: "https://github.com/zeshan0727/NextSolution/tree/main/DailyLedger")!
        ),
        UploadDestination(
            id: "repo-site",
            title: "Sileo Repository Website",
            detail: "Open the package repository and available jailbreak downloads.",
            icon: "shippingbox.fill",
            url: repoURL
        )
    ]

    static let faqItems: [FAQItem] = [
        FAQItem(
            id: "risk",
            question: "Is jailbreaking completely risk-free?",
            answer: "No. Modifying system software can cause instability, security issues, data loss or compatibility problems. Back up your device and use a guide confirmed for your exact model and iOS version."
        ),
        FAQItem(
            id: "remove",
            question: "Can I remove a jailbreak later?",
            answer: "Many jailbreaks include a restore or remove option. A full Finder or iTunes restore may also return the device to stock iOS, depending on the tool and version."
        ),
        FAQItem(
            id: "free",
            question: "Are the tutorials free?",
            answer: "Yes. The written guides, native app content and videos provided by Next Jailbreak are free."
        ),
        FAQItem(
            id: "tweak",
            question: "Why is a tweak not working?",
            answer: "Check the supported iOS version, jailbreak type, architecture, dependencies and whether the package was built for rootless, RootHide or rootful environments."
        ),
        FAQItem(
            id: "download",
            question: "Where are downloaded files saved?",
            answer: "The app stores completed downloads in its Documents folder and immediately presents the iOS share sheet so you can save the file to Files, open it in TrollStore or send it to another compatible app."
        ),
        FAQItem(
            id: "native",
            question: "Does this app load the website internally?",
            answer: "No. The main interface, tabs, lists, tutorial details, video feed, FAQ and downloads are written in SwiftUI. External source pages open only when you intentionally choose Open Full Guide or another outside link."
        )
    ]
}
