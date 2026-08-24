import UIKit

final class BrowserProfilesViewController: UITableViewController {
    typealias OpenProfileHandler = (_ profileIndex: Int, _ openGoogleSignIn: Bool) -> Void

    private let profileStore: BrowserProfileStore
    private let openProfileHandler: OpenProfileHandler
    private var profileObservation: NSObjectProtocol?

    init(profileStore: BrowserProfileStore, openProfileHandler: @escaping OpenProfileHandler) {
        self.profileStore = profileStore
        self.openProfileHandler = openProfileHandler
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let profileObservation {
            NotificationCenter.default.removeObserver(profileObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile Settings"
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = 64
        tableView.accessibilityIdentifier = "browserProfilesTable"

        profileObservation = NotificationCenter.default.addObserver(
            forName: .nextMultiBrowserProfileDidChange,
            object: profileStore,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let profileIndex = notification.userInfo?["profileIndex"] as? Int,
                  (1...BrowserProfileStore.profileCount).contains(profileIndex) else { return }
            self.tableView.reloadRows(
                at: [IndexPath(row: profileIndex - 1, section: 0)],
                with: .none
            )
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        BrowserProfileStore.profileCount
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "20 Separate Browser Profiles"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Each browser has an isolated cookie store. Sign in to a different Google account in every profile; sessions are restored separately after closing the app."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "BrowserProfileCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)

        let profileIndex = indexPath.row + 1
        let snapshot = profileStore.snapshot(for: profileIndex)
        var content = cell.defaultContentConfiguration()
        content.text = snapshot.displayName
        content.secondaryText = snapshot.statusText
        content.image = UIImage(systemName: snapshot.hasGoogleSession ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
        content.imageProperties.tintColor = snapshot.hasGoogleSession ? .systemGreen : .systemBlue
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "browserProfile\(profileIndex)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let profileIndex = indexPath.row + 1
        let controller = BrowserProfileDetailViewController(
            profileIndex: profileIndex,
            profileStore: profileStore,
            openProfileHandler: openProfileHandler
        )
        navigationController?.pushViewController(controller, animated: true)
    }
}

private final class BrowserProfileDetailViewController: UITableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable {
        case profileName
        case session
        case actions
        case data
    }

    private let profileIndex: Int
    private let profileStore: BrowserProfileStore
    private let openProfileHandler: BrowserProfilesViewController.OpenProfileHandler
    private let nameField = UITextField()
    private var profileObservation: NSObjectProtocol?
    private lazy var nameCell: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            nameField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            nameField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
        ])
        cell.selectionStyle = .none
        return cell
    }()

    init(
        profileIndex: Int,
        profileStore: BrowserProfileStore,
        openProfileHandler: @escaping BrowserProfilesViewController.OpenProfileHandler
    ) {
        self.profileIndex = profileIndex
        self.profileStore = profileStore
        self.openProfileHandler = openProfileHandler
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let profileObservation {
            NotificationCenter.default.removeObserver(profileObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = profileStore.displayName(for: profileIndex)
        navigationItem.largeTitleDisplayMode = .never
        tableView.keyboardDismissMode = .interactive

        nameField.text = profileStore.displayName(for: profileIndex)
        nameField.placeholder = "Browser \(profileIndex)"
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.autocorrectionType = .no
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameEditingDidEnd), for: .editingDidEnd)

        profileObservation = NotificationCenter.default.addObserver(
            forName: .nextMultiBrowserProfileDidChange,
            object: profileStore,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let changedIndex = notification.userInfo?["profileIndex"] as? Int,
                  changedIndex == self.profileIndex else { return }
            self.title = self.profileStore.displayName(for: self.profileIndex)
            self.tableView.reloadSections(IndexSet(integer: Section.session.rawValue), with: .none)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveName()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .profileName: return 1
        case .session: return 2
        case .actions: return 2
        case .data: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .profileName: return "Profile Name"
        case .session: return "Saved Session"
        case .actions: return "Open"
        case .data: return "Profile Data"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .data else { return nil }
        return "Clearing this profile signs it out and removes only this browser’s cookies, cache, and website data. Other browser profiles are not affected."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .profileName:
            return nameCell

        case .session:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let snapshot = profileStore.snapshot(for: profileIndex)
            if indexPath.row == 0 {
                cell.textLabel?.text = "Status"
                cell.detailTextLabel?.text = snapshot.statusText
                cell.detailTextLabel?.textColor = snapshot.hasGoogleSession ? .systemGreen : .secondaryLabel
                cell.imageView?.image = UIImage(systemName: snapshot.hasGoogleSession ? "checkmark.shield.fill" : "shield")
            } else {
                cell.textLabel?.text = "Isolation"
                if #available(iOS 17.0, *) {
                    cell.detailTextLabel?.text = "Persistent profile"
                } else {
                    cell.detailTextLabel?.text = "Cookies restored"
                }
                cell.imageView?.image = UIImage(systemName: "shippingbox.fill")
            }
            cell.selectionStyle = .none
            return cell

        case .actions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            if indexPath.row == 0 {
                cell.textLabel?.text = "Open Google Sign-In"
                cell.imageView?.image = UIImage(systemName: "person.badge.key.fill")
            } else {
                cell.textLabel?.text = profileStore.lastURL(for: profileIndex) == nil ? "Open Browser" : "Open Last Page"
                cell.imageView?.image = UIImage(systemName: "safari.fill")
            }
            cell.textLabel?.textColor = view.tintColor
            cell.accessoryType = .disclosureIndicator
            return cell

        case .data:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Clear This Profile"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "trash")
            cell.imageView?.tintColor = .systemRed
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .actions:
            saveName()
            view.endEditing(true)
            openProfileHandler(profileIndex, indexPath.row == 0)

        case .data:
            confirmClearProfile()

        case .profileName, .session:
            break
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveName()
        textField.resignFirstResponder()
        return true
    }

    @objc private func nameEditingDidEnd() {
        saveName()
    }

    private func saveName() {
        profileStore.setDisplayName(nameField.text ?? "", for: profileIndex)
        nameField.text = profileStore.displayName(for: profileIndex)
    }

    private func confirmClearProfile() {
        let name = profileStore.displayName(for: profileIndex)
        let alert = UIAlertController(
            title: "Clear \(name)?",
            message: "This signs out the account in this profile and removes its saved website data.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear Profile", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.profileStore.clearProfile(self.profileIndex) { [weak self] in
                self?.tableView.reloadSections(IndexSet(integer: Section.session.rawValue), with: .automatic)
            }
        })
        present(alert, animated: true)
    }
}
