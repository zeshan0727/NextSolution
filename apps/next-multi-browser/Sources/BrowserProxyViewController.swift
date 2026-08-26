import UIKit
import WebKit
import Network

private struct BrowserProxyProbeResult {
    let profileIndex: Int
    let exitIP: String?
    let errorDescription: String?
}

private final class BrowserProxyProbe {
    static func run(
        profileIndex: Int,
        route: BrowserProxyRoute,
        password: String?,
        completion: @escaping (BrowserProxyProbeResult) -> Void
    ) {
        guard let proxy = route.makeConfiguration(password: password) else {
            completion(BrowserProxyProbeResult(
                profileIndex: profileIndex,
                exitIP: nil,
                errorDescription: "Invalid proxy configuration"
            ))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.proxyConfigurations = [proxy]

        let session = URLSession(configuration: configuration)
        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            completion(BrowserProxyProbeResult(profileIndex: profileIndex, exitIP: nil, errorDescription: "Invalid probe URL"))
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                DispatchQueue.main.async {
                    completion(BrowserProxyProbeResult(
                        profileIndex: profileIndex,
                        exitIP: nil,
                        errorDescription: error.localizedDescription
                    ))
                }
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ip = object["ip"] as? String,
                  !ip.isEmpty else {
                DispatchQueue.main.async {
                    completion(BrowserProxyProbeResult(
                        profileIndex: profileIndex,
                        exitIP: nil,
                        errorDescription: "No exit IP returned"
                    ))
                }
                return
            }

            DispatchQueue.main.async {
                completion(BrowserProxyProbeResult(profileIndex: profileIndex, exitIP: ip, errorDescription: nil))
            }
        }
        task.resume()
    }
}

final class BrowserProxyViewController: UITableViewController {
    private let profileStore: BrowserProfileStore
    private let proxyStore: BrowserProxyStore
    private var observation: NSObjectProtocol?
    private var exitIPs: [Int: String] = [:]
    private var probeErrors: [Int: String] = [:]
    private var isProbing = false

    init(
        profileStore: BrowserProfileStore = .shared,
        proxyStore: BrowserProxyStore = .shared
    ) {
        self.profileStore = profileStore
        self.proxyStore = proxyStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Private IPs"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProxyCell")

        observation = NotificationCenter.default.addObserver(
            forName: .nextMultiBrowserProxyRouteDidChange,
            object: proxyStore,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : BrowserProfileStore.profileCount
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            let count = proxyStore.assignedProfileIndices().count
            return "PRIVATE ROUTING • \(count)/\(BrowserProfileStore.profileCount) ASSIGNED"
        }
        return "ONE PROXY PER BROWSER PROFILE"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "iOS 17+ WebKit routing. Proxy failover is disabled, so a failed assigned proxy does not intentionally fall back to the device's normal route."
        }
        return "Import up to 20 endpoints in profile order. Profiles without an assigned endpoint use the normal device connection."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Import & Assign 1–20 Proxies"
                cell.detailTextLabel?.text = "One endpoint per line, assigned to Browser 1, Browser 2, …"
                cell.imageView?.image = UIImage(systemName: "square.and.arrow.down")
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = isProbing ? "Testing Exit IPs…" : "Verify Assigned Exit IPs"
                cell.detailTextLabel?.text = isProbing ? "Checking each proxy independently" : "Confirms which public IP each assigned profile uses"
                cell.imageView?.image = UIImage(systemName: "checkmark.shield")
                cell.accessoryType = .none
                cell.isUserInteractionEnabled = !isProbing
                cell.textLabel?.textColor = isProbing ? .secondaryLabel : .label
            default:
                cell.textLabel?.text = "Clear All Private IP Routes"
                cell.detailTextLabel?.text = "Return every profile to the normal device connection"
                cell.imageView?.image = UIImage(systemName: "trash")
                cell.textLabel?.textColor = .systemRed
                cell.accessoryType = .none
            }
            return cell
        }

        let profileIndex = indexPath.row + 1
        let profileName = profileStore.displayName(for: profileIndex)
        cell.textLabel?.text = "\(profileIndex). \(profileName)"
        cell.accessoryType = .disclosureIndicator

        guard let route = proxyStore.route(for: profileIndex) else {
            cell.detailTextLabel?.text = "Direct • normal device connection"
            cell.imageView?.image = UIImage(systemName: "network")
            return cell
        }

        var details = "\(route.kind.title) • \(route.displayAddress)"
        if let ip = exitIPs[profileIndex] {
            let duplicates = exitIPs.values.filter { $0 == ip }.count
            details += "\nExit IP: \(ip)"
            if duplicates > 1 {
                details += " • shared by \(duplicates) profiles"
            }
        } else if let error = probeErrors[profileIndex] {
            details += "\nTest failed: \(error)"
        } else {
            details += "\nNot verified yet"
        }
        cell.detailTextLabel?.text = details
        cell.imageView?.image = UIImage(systemName: exitIPs[profileIndex] == nil ? "shield" : "shield.checkered")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0: openImporter()
            case 1: verifyAssignedRoutes()
            default: confirmClearAll()
            }
            return
        }

        presentProfileRouteActions(profileIndex: indexPath.row + 1, sourceIndexPath: indexPath)
    }

    private func openImporter() {
        let importer = BrowserProxyImportViewController { [weak self] parsed in
            guard let self else { return }
            self.exitIPs.removeAll()
            self.probeErrors.removeAll()
            self.proxyStore.replaceAll(with: parsed, profileStore: self.profileStore)
            self.tableView.reloadData()
        }
        let navigation = UINavigationController(rootViewController: importer)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func presentProfileRouteActions(profileIndex: Int, sourceIndexPath: IndexPath) {
        let current = proxyStore.route(for: profileIndex)
        let sheet = UIAlertController(
            title: profileStore.displayName(for: profileIndex),
            message: current.map { "Current: \($0.kind.title) • \($0.displayAddress)" } ?? "Current: Direct",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Set HTTP CONNECT Proxy", style: .default) { [weak self] _ in
            self?.presentRouteEditor(profileIndex: profileIndex, kind: .httpConnect)
        })
        sheet.addAction(UIAlertAction(title: "Set SOCKS5 Proxy", style: .default) { [weak self] _ in
            self?.presentRouteEditor(profileIndex: profileIndex, kind: .socks5)
        })
        if current != nil {
            sheet.addAction(UIAlertAction(title: "Use Direct Connection", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.exitIPs.removeValue(forKey: profileIndex)
                self.probeErrors.removeValue(forKey: profileIndex)
                self.proxyStore.clearRoute(for: profileIndex, profileStore: self.profileStore)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController,
           let cell = tableView.cellForRow(at: sourceIndexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    private func presentRouteEditor(profileIndex: Int, kind: BrowserProxyKind) {
        let current = proxyStore.route(for: profileIndex)
        let currentPassword = proxyStore.password(for: profileIndex)
        let alert = UIAlertController(
            title: "\(kind.title) • Browser \(profileIndex)",
            message: "Enter the private proxy endpoint. Passwords are stored in iOS Keychain.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Host or IP"
            field.text = current?.host
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Port"
            field.keyboardType = .numberPad
            field.text = current.map { String($0.port) }
        }
        alert.addTextField { field in
            field.placeholder = "Username (optional)"
            field.text = current?.username
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = currentPassword == nil ? "Password (optional)" : "Password • leave blank to keep existing"
            field.isSecureTextEntry = true
            field.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let fields = alert?.textFields,
                  fields.count == 4,
                  let host = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !host.isEmpty,
                  let portText = fields[1].text,
                  let port = UInt16(portText),
                  port > 0 else {
                self?.showSimpleAlert(title: "Invalid Proxy", message: "Enter a valid host and port from 1 to 65535.")
                return
            }

            let username = fields[2].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let typedPassword = fields[3].text ?? ""
            let password = typedPassword.isEmpty ? currentPassword : typedPassword
            let route = BrowserProxyRoute(
                kind: kind,
                host: host,
                port: port,
                username: username?.isEmpty == false ? username : nil
            )
            self.exitIPs.removeValue(forKey: profileIndex)
            self.probeErrors.removeValue(forKey: profileIndex)
            self.proxyStore.setRoute(route, password: password, for: profileIndex, profileStore: self.profileStore)
        })
        present(alert, animated: true)
    }

    private func verifyAssignedRoutes() {
        let indices = proxyStore.assignedProfileIndices()
        guard !indices.isEmpty, !isProbing else {
            if indices.isEmpty {
                showSimpleAlert(title: "No Private Routes", message: "Assign at least one proxy first.")
            }
            return
        }

        isProbing = true
        exitIPs.removeAll()
        probeErrors.removeAll()
        tableView.reloadSections(IndexSet(integer: 0), with: .none)

        let group = DispatchGroup()
        let lock = NSLock()
        var results: [BrowserProxyProbeResult] = []

        for index in indices {
            guard let route = proxyStore.route(for: index) else { continue }
            group.enter()
            BrowserProxyProbe.run(
                profileIndex: index,
                route: route,
                password: proxyStore.password(for: index)
            ) { result in
                lock.lock()
                results.append(result)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            for result in results {
                if let ip = result.exitIP {
                    self.exitIPs[result.profileIndex] = ip
                } else if let error = result.errorDescription {
                    self.probeErrors[result.profileIndex] = error
                }
            }
            self.isProbing = false
            self.tableView.reloadData()

            let successful = self.exitIPs.count
            let unique = Set(self.exitIPs.values).count
            let failed = self.probeErrors.count
            self.showSimpleAlert(
                title: "Private IP Check Complete",
                message: "\(successful) route(s) passed, \(unique) unique exit IP(s), \(failed) failed."
            )
        }
    }

    private func confirmClearAll() {
        guard !proxyStore.assignedProfileIndices().isEmpty else { return }
        let alert = UIAlertController(
            title: "Clear all private routes?",
            message: "All 20 profiles will return to the normal device connection.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.exitIPs.removeAll()
            self.probeErrors.removeAll()
            self.proxyStore.clearAll(profileStore: self.profileStore)
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func showSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class BrowserProxyImportViewController: UIViewController {
    private let completion: ([BrowserProxyParsedRoute]) -> Void
    private let textView = UITextView()
    private let summaryLabel = UILabel()

    init(completion: @escaping ([BrowserProxyParsedRoute]) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Import Private Proxies"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Assign",
            style: .done,
            target: self,
            action: #selector(assign)
        )

        let instructions = UILabel()
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .subheadline)
        instructions.textColor = .secondaryLabel
        instructions.text = "Paste one proxy per line. The first line goes to Browser 1, the second to Browser 2, up to Browser 20.\n\nAccepted formats:\nhttp://user:pass@host:port\nsocks5://user:pass@host:port\nhost:port\nhost:port:username:password"

        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.keyboardType = .URL
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.cornerRadius = 10
        textView.delegate = self

        summaryLabel.numberOfLines = 0
        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.text = "0 valid proxies detected"

        let stack = UIStackView(arrangedSubviews: [instructions, textView, summaryLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func assign() {
        let parsed = BrowserProxyParser.parse(textView.text)
        guard !parsed.isEmpty else {
            let alert = UIAlertController(
                title: "No Valid Proxies",
                message: "Paste at least one supported proxy endpoint.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        completion(Array(parsed.prefix(BrowserProfileStore.profileCount)))
        dismiss(animated: true)
    }
}

extension BrowserProxyImportViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let count = BrowserProxyParser.parse(textView.text).count
        if count > BrowserProfileStore.profileCount {
            summaryLabel.text = "\(count) valid proxies detected • first 20 will be assigned"
        } else {
            summaryLabel.text = "\(count) valid prox\(count == 1 ? "y" : "ies") detected • \(count) profile\(count == 1 ? "" : "s") will use private routing"
        }
    }
}

extension BrowserGridViewController {
    func reloadWebViewsAfterProxyRouteChange() {
        let webViews = view.nextMultiBrowserDescendantWebViews
        for webView in webViews {
            webView.stopLoading()
            if let url = webView.url,
               url.scheme == "http" || url.scheme == "https" {
                webView.load(URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: 60
                ))
            } else {
                webView.reload()
            }
        }
    }
}

private extension UIView {
    var nextMultiBrowserDescendantWebViews: [WKWebView] {
        var result: [WKWebView] = []
        for child in subviews {
            if let webView = child as? WKWebView {
                result.append(webView)
            }
            result.append(contentsOf: child.nextMultiBrowserDescendantWebViews)
        }
        return result
    }
}
