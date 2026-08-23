import UIKit

final class VPNGateViewController: UITableViewController, UISearchResultsUpdating {
    private let manager = VPNGateManager.shared
    private let searchController = UISearchController(searchResultsController: nil)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var allServers: [VPNGateServer] = []
    private var sections: [(country: String, code: String, servers: [VPNGateServer])] = []
    private var isConnecting = false

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
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Disconnect", style: .plain, target: self, action: #selector(disconnectVPN)),
            UIBarButtonItem(customView: spinner)
        ]

        tableView.tableHeaderView = makeNoticeHeader()
        loadServers()
    }

    private func makeNoticeHeader() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.text = "VPN Gate uses public volunteer-operated VPN relay servers. Server availability, logging, speed and privacy vary by operator. These servers are not operated by Next Multi Browser."
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        container.frame.size.height = 86
        return container
    }

    private func loadServers() {
        spinner.startAnimating()
        Task {
            do {
                let servers = try await manager.fetchServers()
                await MainActor.run {
                    self.spinner.stopAnimating()
                    self.allServers = servers
                    self.rebuildSections(query: self.searchController.searchBar.text)
                }
            } catch {
                await MainActor.run {
                    self.spinner.stopAnimating()
                    self.showError(error)
                }
            }
        }
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

        Task {
            do {
                try await manager.connect(to: server)
                await MainActor.run {
                    self.isConnecting = false
                    self.spinner.stopAnimating()
                    self.navigationItem.prompt = "VPN requested • \(server.countryName)"
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.spinner.stopAnimating()
                    self.navigationItem.prompt = nil
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
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
