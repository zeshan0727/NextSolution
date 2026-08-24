import UIKit
import WebKit

final class BrowserProfileStorageViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case summary
        case categories
        case location
        case action
    }

    private let profileIndex: Int
    private let profileStore: BrowserProfileStore
    private var storage = BrowserProfileStorageSnapshot.empty()
    private var isLoading = false

    init(profileIndex: Int, profileStore: BrowserProfileStore) {
        self.profileIndex = profileIndex
        self.profileStore = profileStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Storage"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshStorage)
        )
        refreshStorage()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .summary: return 2
        case .categories: return 5
        case .location: return 1
        case .action: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .summary: return "Website Data"
        case .categories: return "Storage Types"
        case .location: return "Persistent Storage Location"
        case .action: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .categories where storage.isManagedByWebKit:
            return "This OS stores named WebKit profiles in a system-managed location. Website record and cookie counts remain available; public WebKit APIs do not expose exact physical sizes."
        case .action:
            return "Clear All Website Data affects Browser \(profileIndex) only. Other profile containers and saved logins remain untouched."
        default:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .summary:
            if indexPath.row == 0 {
                return valueCell(
                    "Total Profile Data",
                    value: isLoading ? "Calculating…" : BrowserProfileFormatting.bytes(storage.totalWebsiteDataBytes),
                    symbol: "internaldrive.fill"
                )
            }
            return valueCell(
                "Website Records",
                value: "\(storage.websiteRecordCount)",
                symbol: "list.bullet.rectangle"
            )

        case .categories:
            switch indexPath.row {
            case 0:
                return valueCell(
                    "Cookies",
                    value: "\(storage.cookieCount) • \(BrowserProfileFormatting.bytes(storage.cookiesBytes))",
                    symbol: "circle.grid.cross.fill"
                )
            case 1:
                return valueCell(
                    "Cache",
                    value: BrowserProfileFormatting.bytes(storage.cacheBytes),
                    symbol: "bolt.horizontal.circle.fill"
                )
            case 2:
                return valueCell(
                    "Local Storage",
                    value: BrowserProfileFormatting.bytes(storage.localStorageBytes),
                    symbol: "folder.fill"
                )
            case 3:
                return valueCell(
                    "IndexedDB",
                    value: BrowserProfileFormatting.bytes(storage.indexedDBBytes),
                    symbol: "cylinder.split.1x2.fill"
                )
            default:
                return valueCell(
                    "Other Website Data",
                    value: BrowserProfileFormatting.bytes(storage.otherWebsiteDataBytes),
                    symbol: "square.stack.3d.up.fill"
                )
            }

        case .location:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = profileStore.storageLocationDescription(for: profileIndex)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.text = "Profile \(profileIndex) has its own directory or named WebKit store."
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            return cell

        case .action:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Clear All Website Data"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "trash.slash.fill")
            cell.imageView?.tintColor = .systemRed
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .action, !isLoading else { return }
        let alert = UIAlertController(
            title: "Clear Profile Website Data?",
            message: "Cookies, cache, local storage, IndexedDB, service workers, and other site data will be removed only from \(profileStore.displayName(for: profileIndex)).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.setLoading(true)
            self.profileStore.clearProfile(self.profileIndex) { [weak self] in
                self?.refreshStorage()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        })
        present(alert, animated: true)
    }

    @objc private func refreshStorage() {
        setLoading(true)
        profileStore.inspectStorage(for: profileIndex) { [weak self] value in
            guard let self else { return }
            self.storage = value
            self.setLoading(false)
        }
    }

    private func setLoading(_ loading: Bool) {
        isLoading = loading
        tableView.isUserInteractionEnabled = !loading
        if loading {
            let activity = UIActivityIndicatorView(style: .medium)
            activity.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activity)
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(refreshStorage)
            )
        }
        tableView.reloadData()
    }

    private func valueCell(_ title: String, value: String, symbol: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = value
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: symbol)
        cell.imageView?.tintColor = view.tintColor
        cell.selectionStyle = .none
        return cell
    }
}
final class BrowserProfileDebugViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case profile
        case storage
        case environment
        case userAgent
        case copy
    }

    private let profileIndex: Int
    private let profileStore: BrowserProfileStore
    private var storage = BrowserProfileStorageSnapshot.empty()
    private var resolvedUserAgent = "Resolving System WebKit user agent…"
    private var userAgentProbe: WKWebView?

    init(profileIndex: Int, profileStore: BrowserProfileStore) {
        self.profileIndex = profileIndex
        self.profileStore = profileStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Developer Information"
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
        refresh()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .profile: return 5
        case .storage: return 5
        case .environment: return 5
        case .userAgent: return 1
        case .copy: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .profile: return "Current Profile"
        case .storage: return "Storage"
        case .environment: return "Environment"
        case .userAgent: return "Effective User Agent"
        case .copy: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .environment else { return nil }
        return "Viewport and environment presets are compatibility-testing controls. They do not alter the physical iPhone or network address."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let snapshot = profileStore.snapshot(for: profileIndex)
        let environment = snapshot.environment

        switch Section(rawValue: indexPath.section)! {
        case .profile:
            switch indexPath.row {
            case 0: return valueCell("Name", snapshot.displayName)
            case 1: return valueCell("Profile Slot", "Browser \(profileIndex)")
            case 2: return valueCell("Store ID", profileStore.persistentIdentifier(for: profileIndex).uuidString)
            case 3: return valueCell("Persistence", profileStore.persistenceDescription(for: profileIndex))
            default: return valueCell("Last Used", BrowserProfileFormatting.lastUsed(snapshot.lastUsed))
            }

        case .storage:
            switch indexPath.row {
            case 0:
                return valueCell(
                    "Cookies",
                    "\(storage.cookieCount) • \(BrowserProfileFormatting.bytes(storage.cookiesBytes))"
                )
            case 1: return valueCell("Cache", BrowserProfileFormatting.bytes(storage.cacheBytes))
            case 2: return valueCell("Local Storage", BrowserProfileFormatting.bytes(storage.localStorageBytes))
            case 3: return valueCell("IndexedDB", BrowserProfileFormatting.bytes(storage.indexedDBBytes))
            default: return valueCell("Website Data", BrowserProfileFormatting.bytes(storage.totalWebsiteDataBytes))
            }

        case .environment:
            switch indexPath.row {
            case 0: return valueCell("Device", environment.viewport.title)
            case 1: return valueCell("Viewport", environment.viewport.viewportDescription)
            case 2: return valueCell("Language / Locale", "\(environment.language.title) • \(environment.localeIdentifier)")
            case 3: return valueCell("Region", "\(environment.region.title) • \(environment.region.regionCode ?? "Device")")
            default: return valueCell("Timezone", environment.timezone.identifier ?? "Automatic")
            }

        case .userAgent:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = environment.userAgent.title
            cell.detailTextLabel?.text = resolvedUserAgent
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.selectionStyle = .none
            return cell

        case .copy:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Copy Debug Information"
            cell.textLabel?.textColor = view.tintColor
            cell.imageView?.image = UIImage(systemName: "doc.on.doc.fill")
            cell.imageView?.tintColor = view.tintColor
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .copy else { return }
        UIPasteboard.general.string = debugReport()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let alert = UIAlertController(
            title: "Copied",
            message: "Developer information for this profile is ready to paste.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func refresh() {
        profileStore.inspectStorage(for: profileIndex) { [weak self] value in
            guard let self else { return }
            self.storage = value
            self.tableView.reloadSections(
                IndexSet(integer: Section.storage.rawValue),
                with: .none
            )
        }
        resolveUserAgent()
    }

    private func resolveUserAgent() {
        let environment = profileStore.environment(for: profileIndex)
        if let userAgent = environment.userAgent.userAgent {
            resolvedUserAgent = userAgent
            return
        }

        let session = profileStore.session(for: profileIndex)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.dataStore
        configuration.processPool = session.processPool
        BrowserEnvironmentWebKit.configure(environment, configuration: configuration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        userAgentProbe = webView
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] value, _ in
            guard let self else { return }
            if let value = value as? String, !value.isEmpty {
                self.resolvedUserAgent = value
            } else {
                self.resolvedUserAgent = "System WebKit"
            }
            self.userAgentProbe = nil
            self.tableView.reloadSections(
                IndexSet(integer: Section.userAgent.rawValue),
                with: .none
            )
        }
    }

    private func valueCell(_ title: String, _ value: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = value
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
        cell.detailTextLabel?.minimumScaleFactor = 0.55
        cell.selectionStyle = .none
        return cell
    }

    private func debugReport() -> String {
        let snapshot = profileStore.snapshot(for: profileIndex)
        let environment = snapshot.environment
        return """
        Next Multi Browser — Profile Debug Information

        Profile
        Name: \(snapshot.displayName)
        Slot: Browser \(profileIndex)
        Store ID: \(profileStore.persistentIdentifier(for: profileIndex).uuidString)
        Persistence: \(profileStore.persistenceDescription(for: profileIndex))
        Storage Location: \(profileStore.storageLocationDescription(for: profileIndex))
        Last Used: \(BrowserProfileFormatting.dateAndTime(snapshot.lastUsed))

        Storage
        Cookies: \(storage.cookieCount) (\(BrowserProfileFormatting.bytes(storage.cookiesBytes)))
        Cache: \(BrowserProfileFormatting.bytes(storage.cacheBytes))
        Local Storage: \(BrowserProfileFormatting.bytes(storage.localStorageBytes))
        IndexedDB: \(BrowserProfileFormatting.bytes(storage.indexedDBBytes))
        Website Data: \(BrowserProfileFormatting.bytes(storage.totalWebsiteDataBytes))
        Website Records: \(storage.websiteRecordCount)

        Environment
        Device: \(environment.viewport.title)
        Viewport: \(environment.viewport.viewportDescription)
        User Agent Preset: \(environment.userAgent.title)
        User Agent: \(resolvedUserAgent)
        Language: \(environment.language.title)
        Locale: \(environment.localeIdentifier)
        Region: \(environment.region.title)
        Timezone: \(environment.timezone.identifier ?? "Automatic")
        """
    }
}
