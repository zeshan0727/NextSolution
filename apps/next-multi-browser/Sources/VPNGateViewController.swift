import UIKit

final class VPNGateViewController: UITableViewController, UISearchResultsUpdating {
    private let manager = VPNGateManager.shared
    private let searchController = UISearchController(searchResultsController: nil)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var allServers: [VPNGateServer] = []
    private var sections: [(country: String, code: String, servers: [VPNGateServer])] = []
    private var isConnecting = false
    private var isLoadingServers = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Free VPN Servers"
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 62

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search country or server"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        updateRightItems()

        tableView.tableHeaderView = makeNoticeHeader()
        loadServers(showFailureAlert: true)
    }

    private func makeNoticeHeader() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.text = "VPN Gate uses public volunteer-operated VPN relay servers. Server availability, logging, speed and privacy vary by operator. If the main feed is slow, this app automatically tries VPN Gate mirrors and then a cached last-good list."
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        container.frame.size.height = 104
        return container
    }

    private func updateRightItems() {
        let refresh = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refreshServers))
        refresh.accessibilityLabel = "Refresh VPN servers"
        refresh.isEnabled = !isLoadingServers && !isConnecting
        let disconnect = UIBarButtonItem(title: "Disconnect", style: .plain, target: self, action: #selector(disconnectVPN))
        disconnect.isEnabled = !isConnecting
        navigationItem.rightBarButtonItems = [disconnect, refresh, UIBarButtonItem(customView: spinner)]
    }

    private func loadServers(showFailureAlert: Bool) {
        guard !isLoadingServers else { return }
        isLoadingServers = true
        spinner.startAnimating()
        navigationItem.prompt = "Searching live server feeds and mirrors…"
        updateRightItems()

        Task {
            do {
                let servers = try await manager.fetchServers()
                await MainActor.run {
                    self.isLoadingServers = false
                    self.spinner.stopAnimating()
                    self.allServers = servers
                    self.rebuildSections(query: self.searchController.searchBar.text)
                    if self.manager.lastFetchUsedCache {
                        self.navigationItem.prompt = "Using cached server list • Refresh to retry live feeds"
                    } else if let source = self.manager.lastSuccessfulFeedDescription {
                        self.navigationItem.prompt = "Live servers loaded • \(source)"
                    } else {
                        self.navigationItem.prompt = "Live servers loaded"
                    }
                    self.updateRightItems()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingServers = false
                    self.spinner.stopAnimating()
                    self.navigationItem.prompt = "Server list unavailable"
                    self.updateRightItems()
                    if showFailureAlert { self.showError(error) }
                }
            }
        }
    }

    @objc private func refreshServers() {
        loadServers(showFailureAlert: true)
    }

    private func rebuildSections(query: String?) {
        let needle = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [VPNGateServer]
        if needle.isEmpty {
            filtered = allServers
        } else {
            filtered = allServers.filter {
                $0.countryName.lowercased().contains(needle) ||
                $0.countryCode.lowercased().contains(needle) ||
                $0.hostName.lowercased().contains(needle) ||
                $0.ipAddress.lowercased().contains(needle)
            }
        }

        let grouped = Dictionary(grouping: filtered) { "\($0.countryName)|\($0.countryCode)" }
        sections = grouped.map { key, values in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return (
                country: parts.first ?? "Unknown",
                code: parts.count > 1 ? parts[1] : "",
                servers: values.sorted {
                    if $0.score == $1.score { return $0.speed > $1.speed }
                    return $0.score > $1.score
                }
            )
        }.sorted {
            $0.country.localizedCaseInsensitiveCompare($1.country) == .orderedAscending
        }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        rebuildSections(query: searchController.searchBar.text)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].servers.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let item = sections[section]
        return item.code.isEmpty ? item.country : "\(item.country) • \(item.code)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "vpn-server"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let server = sections[indexPath.section].servers[indexPath.row]

        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cell.textLabel?.text = server.hostName.isEmpty ? server.ipAddress : server.hostName
        let ping = server.ping.map { "\($0) ms" } ?? "ping n/a"
        cell.detailTextLabel?.text = String(format: "%@ • %.1f Mbps • score %d", ping, server.speedMbps, server.score)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = manager.connectedServer == server ? .checkmark : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isConnecting else { return }
        let server = sections[indexPath.section].servers[indexPath.row]

        let alert = UIAlertController(
            title: "Connect to \(server.countryName)?",
            message: "This routes device traffic through a public volunteer VPN server. On first use iOS may ask you to allow a VPN configuration.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            self?.connect(to: server)
        })
        present(alert, animated: true)
    }

    private func connect(to server: VPNGateServer) {
        isConnecting = true
        spinner.startAnimating()
        navigationItem.prompt = "Connecting to \(server.countryName)…"
        updateRightItems()

        Task {
            do {
                try await manager.connect(to: server)
                await MainActor.run {
                    self.isConnecting = false
                    self.spinner.stopAnimating()
                    self.navigationItem.prompt = "VPN requested • \(server.countryName)"
                    self.tableView.reloadData()
                    self.updateRightItems()
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.spinner.stopAnimating()
                    self.navigationItem.prompt = nil
                    self.updateRightItems()
                    self.showError(error)
                }
            }
        }
    }

    @objc private func disconnectVPN() {
        spinner.startAnimating()
        Task {
            await manager.disconnect()
            await MainActor.run {
                self.spinner.stopAnimating()
                self.navigationItem.prompt = "VPN disconnected"
                self.tableView.reloadData()
            }
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "VPN Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.loadServers(showFailureAlert: true)
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }
}
