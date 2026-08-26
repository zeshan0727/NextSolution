import UIKit

final class BrowserProfilesViewController: UITableViewController {
    typealias OpenProfileHandler = (_ profileIndex: Int, _ openGoogleSignIn: Bool) -> Void

    private enum Section: Int, CaseIterable {
        case globalEnvironment
        case profiles
    }

    private let profileStore: BrowserProfileStore
    private let openProfileHandler: OpenProfileHandler
    private var profileObservation: NSObjectProtocol?
    private var storageRefreshes = Set<Int>()
    private lazy var sessionTransferController = BrowserSessionTransferController(
        profileStore: profileStore,
        presenter: self
    )

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
        title = "Profiles"
        navigationItem.largeTitleDisplayMode = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 94
        tableView.accessibilityIdentifier = "browserProfilesTable"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Transfer",
            style: .plain,
            target: self,
            action: #selector(openSessionTransfer)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshStorage)
        )

        profileObservation = NotificationCenter.default.addObserver(
            forName: .nextMultiBrowserProfileDidChange,
            object: profileStore,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.isViewLoaded,
                  let profileIndex = notification.userInfo?["profileIndex"] as? Int,
                  (1...BrowserProfileStore.profileCount).contains(profileIndex) else { return }
            let indexPath = IndexPath(
                row: profileIndex - 1,
                section: Section.profiles.rawValue
            )
            if self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData()
        refreshStorage()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .globalEnvironment: return 1
        case .profiles: return BrowserProfileStore.profileCount
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .globalEnvironment: return "Global Environment"
        case .profiles: return "20 Isolated Browser Profiles"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .globalEnvironment:
            return "Randomizes phone, user agent, language, region, and timezone for every profile. Cookies, logins, and website data remain untouched."
        case .profiles:
            return "Every profile keeps its own persistent WebKit store, process pool, cookies, local storage, IndexedDB, cache, environment, and website permissions."
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .globalEnvironment {
            let identifier = "RandomizeAllEnvironmentsCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
            var content = cell.defaultContentConfiguration()
            content.text = "Randomize All Environments"
            content.textProperties.color = view.tintColor
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = "20 profiles • Unique phone-based combinations"
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: "shuffle")
            content.imageProperties.tintColor = view.tintColor
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.accessibilityIdentifier = "randomizeAllProfileEnvironments"
            cell.accessibilityHint = "Randomizes all profile environments without clearing login or website data."
            return cell
        }

        let identifier = "BrowserProfileCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)

        let profileIndex = indexPath.row + 1
        let snapshot = profileStore.snapshot(for: profileIndex)
        var content = cell.defaultContentConfiguration()
        content.text = snapshot.displayName
        let sessionLine = snapshot.hasGoogleSession
            ? "Google session saved"
            : snapshot.statusText
        content.secondaryText = """
        \(sessionLine)
        Last used: \(BrowserProfileFormatting.lastUsed(snapshot.lastUsed)) • Storage: \(BrowserProfileFormatting.bytes(snapshot.cachedStorageSize))
        \(snapshot.environment.summary)
        """
        content.secondaryTextProperties.numberOfLines = 3
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        content.image = UIImage(systemName: snapshot.icon.symbolName)
        content.imageProperties.tintColor = snapshot.hasGoogleSession
            ? .systemGreen
            : snapshot.color.uiColor
        content.imageProperties.maximumSize = CGSize(width: 32, height: 32)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "browserProfile\(profileIndex)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .globalEnvironment {
            confirmRandomizeAllEnvironments()
            return
        }
        let profileIndex = indexPath.row + 1
        let controller = BrowserProfileDetailViewController(
            profileIndex: profileIndex,
            profileStore: profileStore,
            openProfileHandler: openProfileHandler
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func openSessionTransfer() {
        guard let item = navigationItem.leftBarButtonItem else { return }
        sessionTransferController.presentMenu(from: item)
    }

    @objc private func refreshStorage() {
        for index in 1...BrowserProfileStore.profileCount where !storageRefreshes.contains(index) {
            storageRefreshes.insert(index)
            profileStore.inspectStorage(
                for: index,
                includeWebsiteRecords: false
            ) { [weak self] _ in
                guard let self else { return }
                self.storageRefreshes.remove(index)
                let indexPath = IndexPath(
                    row: index - 1,
                    section: Section.profiles.rawValue
                )
                if self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }
            }
        }
    }

    private func confirmRandomizeAllEnvironments() {
        let alert = UIAlertController(
            title: "Randomize All 20 Profiles?",
            message: "Each browser will receive a new phone-only device, user agent, language, region, and timezone combination. Cookies, Google logins, and website storage remain untouched.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Randomize All", style: .default) { [weak self] _ in
            guard let self else { return }
            let environments = self.profileStore.randomizeAllEnvironments()
            guard environments.count == BrowserProfileStore.profileCount else {
                let error = UIAlertController(
                    title: "Could Not Randomize",
                    message: "The profile environments could not be generated. Please try again.",
                    preferredStyle: .alert
                )
                error.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(error, animated: true)
                return
            }
            UIView.transition(
                with: self.tableView,
                duration: 0.3,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    self.tableView.reloadSections(
                        IndexSet(integer: Section.profiles.rawValue),
                        with: .none
                    )
                },
                completion: nil
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }
}

final class BrowserProfileDetailViewController: UITableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable {
        case identity
        case environment
        case session
        case storage
        case actions
        case privacy
        case danger
    }

    private enum ActionRow: Int {
        case openProfile
        case googleSignIn
        case duplicate
        case backup
        case restore
        case debug
    }

    private let profileIndex: Int
    private let profileStore: BrowserProfileStore
    private let openProfileHandler: BrowserProfilesViewController.OpenProfileHandler
    private let nameField = UITextField()
    private var profileObservation: NSObjectProtocol?
    private var storageSnapshot: BrowserProfileStorageSnapshot?
    private var isWorking = false {
        didSet { updateWorkingState() }
    }

    private lazy var nameCell: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            nameField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            nameField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            nameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
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
        tableView.rowHeight = UITableView.automaticDimension

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
            guard !self.isWorking else { return }
            let sections = IndexSet(
                Section.allCases
                    .filter { $0 != .identity }
                    .map(\.rawValue)
            )
            self.tableView.reloadSections(sections, with: .none)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        inspectStorage()
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
        case .identity: return 2
        case .environment: return 1
        case .session: return 3
        case .storage: return 1
        case .actions: return 6
        case .privacy: return 2
        case .danger: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .identity: return "Profile"
        case .environment: return "Profile Environment"
        case .session: return "Session"
        case .storage: return "Storage"
        case .actions: return "Profile Actions"
        case .privacy: return "Website Privacy"
        case .danger: return "Delete"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .environment:
            return "Environment choices affect this profile only. Existing cookies and login storage are not moved or merged."
        case .privacy:
            return "Clear Website Data removes cookies, cache, local storage, IndexedDB, and other site data from this profile only."
        case .danger:
            return "Delete resets this fixed browser slot to a new blank profile and removes its latest backup. Other profiles are unchanged."
        default:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .identity:
            if indexPath.row == 0 { return nameCell }
            let snapshot = profileStore.snapshot(for: profileIndex)
            return valueCell(
                title: "Icon & Color",
                value: "\(snapshot.icon.title) • \(snapshot.color.title)",
                symbol: snapshot.icon.symbolName,
                tint: snapshot.color.uiColor,
                disclosure: true
            )

        case .environment:
            let environment = profileStore.environment(for: profileIndex)
            return subtitleCell(
                title: "Environment Manager",
                subtitle: environment.summary,
                symbol: "slider.horizontal.3",
                disclosure: true
            )

        case .session:
            let snapshot = profileStore.snapshot(for: profileIndex)
            switch indexPath.row {
            case 0:
                return valueCell(
                    title: "Status",
                    value: snapshot.statusText,
                    symbol: snapshot.hasGoogleSession ? "checkmark.shield.fill" : "shield",
                    tint: snapshot.hasGoogleSession ? .systemGreen : .secondaryLabel
                )
            case 1:
                return valueCell(
                    title: "Last Used",
                    value: BrowserProfileFormatting.lastUsed(snapshot.lastUsed),
                    symbol: "clock"
                )
            default:
                return valueCell(
                    title: "Isolation",
                    value: profileStore.persistenceDescription(for: profileIndex),
                    symbol: "shippingbox.fill"
                )
            }

        case .storage:
            let total = storageSnapshot?.totalWebsiteDataBytes
                ?? profileStore.snapshot(for: profileIndex).cachedStorageSize
            return subtitleCell(
                title: "Storage Management",
                subtitle: "\(BrowserProfileFormatting.bytes(total)) • Cookies, cache, local storage & IndexedDB",
                symbol: "internaldrive.fill",
                disclosure: true
            )

        case .actions:
            let row = ActionRow(rawValue: indexPath.row)!
            switch row {
            case .openProfile:
                return actionCell("Open Profile", symbol: "safari.fill")
            case .googleSignIn:
                return actionCell("Open Google Sign-In", symbol: "person.badge.key.fill")
            case .duplicate:
                return actionCell("Duplicate Profile", symbol: "plus.square.on.square")
            case .backup:
                let lastBackup = profileStore.snapshot(for: profileIndex).lastBackupDate
                return actionCell(
                    lastBackup == nil ? "Backup Profile" : "Backup Profile • Updated \(BrowserProfileFormatting.lastUsed(lastBackup))",
                    symbol: "externaldrive.badge.plus"
                )
            case .restore:
                let cell = actionCell("Restore Profile", symbol: "arrow.counterclockwise.icloud")
                let available = profileStore.hasBackup(for: profileIndex)
                cell.isUserInteractionEnabled = available
                cell.textLabel?.textColor = available ? view.tintColor : .tertiaryLabel
                cell.imageView?.tintColor = available ? view.tintColor : .tertiaryLabel
                return cell
            case .debug:
                return actionCell("Developer Information", symbol: "ladybug.fill")
            }

        case .privacy:
            if indexPath.row == 0 {
                let count = profileStore.snapshot(for: profileIndex).savedPermissionCount
                return valueCell(
                    title: "Reset Website Permissions",
                    value: count == 0 ? "No saved choices" : "\(count) saved",
                    symbol: "camera.badge.ellipsis"
                )
            }
            let cell = actionCell("Clear All Website Data", symbol: "eraser.fill")
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.tintColor = .systemRed
            return cell

        case .danger:
            let cell = actionCell("Delete Profile", symbol: "trash.fill")
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.tintColor = .systemRed
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isWorking else { return }
        saveName()
        view.endEditing(true)

        switch Section(rawValue: indexPath.section)! {
        case .identity where indexPath.row == 1:
            navigationController?.pushViewController(
                BrowserProfileAppearanceViewController(
                    profileIndex: profileIndex,
                    profileStore: profileStore
                ),
                animated: true
            )

        case .environment:
            navigationController?.pushViewController(
                BrowserProfileEnvironmentViewController(
                    profileIndex: profileIndex,
                    profileStore: profileStore
                ),
                animated: true
            )

        case .storage:
            navigationController?.pushViewController(
                BrowserProfileStorageViewController(
                    profileIndex: profileIndex,
                    profileStore: profileStore
                ),
                animated: true
            )

        case .actions:
            handleAction(ActionRow(rawValue: indexPath.row)!)

        case .privacy where indexPath.row == 0:
            confirmResetPermissions()

        case .privacy:
            confirmClearProfile()

        case .danger:
            confirmDeleteProfile()

        case .identity, .session:
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

    private func handleAction(_ action: ActionRow) {
        switch action {
        case .openProfile:
            openProfileHandler(profileIndex, false)
        case .googleSignIn:
            openProfileHandler(profileIndex, true)
        case .duplicate:
            duplicateProfile()
        case .backup:
            backupProfile()
        case .restore:
            confirmRestoreProfile()
        case .debug:
            navigationController?.pushViewController(
                BrowserProfileDebugViewController(
                    profileIndex: profileIndex,
                    profileStore: profileStore
                ),
                animated: true
            )
        }
    }

    private func saveName() {
        profileStore.setDisplayName(nameField.text ?? "", for: profileIndex)
        nameField.text = profileStore.displayName(for: profileIndex)
    }

    private func inspectStorage() {
        profileStore.inspectStorage(for: profileIndex) { [weak self] value in
            guard let self else { return }
            self.storageSnapshot = value
            self.tableView.reloadSections(
                IndexSet(integer: Section.storage.rawValue),
                with: .none
            )
        }
    }

    private func duplicateProfile() {
        isWorking = true
        profileStore.duplicateProfile(profileIndex) { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let target):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.showMessage(
                    title: "Profile Duplicated",
                    message: "Settings were copied to \(self.profileStore.displayName(for: target)) in Browser \(target). It has a new independent storage container; login and website data were not copied."
                )
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.showMessage(title: "Couldn’t Duplicate", message: error.localizedDescription)
            }
        }
    }

    private func backupProfile() {
        isWorking = true
        profileStore.createBackup(for: profileIndex) { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let date):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.showMessage(
                    title: "Backup Complete",
                    message: "Profile preferences, cookies, and available website data were backed up at \(BrowserProfileFormatting.dateAndTime(date))."
                )
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.showMessage(title: "Backup Failed", message: error.localizedDescription)
            }
        }
    }

    private func confirmRestoreProfile() {
        let alert = UIAlertController(
            title: "Restore \(profileStore.displayName(for: profileIndex))?",
            message: "This replaces the selected profile’s current settings and website data with its latest backup. Other profiles are not affected.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            self?.restoreProfile()
        })
        present(alert, animated: true)
    }

    private func restoreProfile() {
        isWorking = true
        profileStore.restoreLatestBackup(for: profileIndex) { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let value):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let restartNote = value.restartRequiredForFullWebsiteData
                    ? " Close and reopen the app once to finish restoring the full on-disk website data."
                    : ""
                self.showMessage(
                    title: "Profile Restored",
                    message: "Restored the backup from \(BrowserProfileFormatting.dateAndTime(value.backupDate)).\(restartNote)"
                )
                self.nameField.text = self.profileStore.displayName(for: self.profileIndex)
                self.inspectStorage()
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.showMessage(title: "Restore Failed", message: error.localizedDescription)
            }
        }
    }

    private func confirmResetPermissions() {
        let name = profileStore.displayName(for: profileIndex)
        let alert = UIAlertController(
            title: "Reset Permissions?",
            message: "Saved camera and microphone decisions for \(name) will be removed. Websites will ask again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.profileStore.resetWebsitePermissions(self.profileIndex)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }

    private func confirmClearProfile() {
        let name = profileStore.displayName(for: profileIndex)
        let alert = UIAlertController(
            title: "Clear \(name)?",
            message: "This signs out this profile and removes only its cookies, cache, local storage, IndexedDB, and website data.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear Website Data", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.isWorking = true
            self.profileStore.clearProfile(self.profileIndex) { [weak self] in
                guard let self else { return }
                self.isWorking = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.inspectStorage()
            }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteProfile() {
        let name = profileStore.displayName(for: profileIndex)
        let alert = UIAlertController(
            title: "Delete \(name)?",
            message: "This permanently clears this profile’s website data, environment, permissions, name, appearance, and latest backup. Browser \(profileIndex) returns as a blank isolated slot.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete Profile", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.isWorking = true
            self.profileStore.deleteProfile(self.profileIndex) { [weak self] in
                guard let self else { return }
                self.isWorking = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.navigationController?.popViewController(animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func updateWorkingState() {
        guard isViewLoaded else { return }
        tableView.isUserInteractionEnabled = !isWorking
        if isWorking {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            navigationItem.rightBarButtonItem = nil
            tableView.reloadData()
        }
    }

    private func valueCell(
        title: String,
        value: String,
        symbol: String,
        tint: UIColor = .secondaryLabel,
        disclosure: Bool = false
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = value
        cell.detailTextLabel?.textColor = tint
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
        cell.detailTextLabel?.minimumScaleFactor = 0.75
        cell.imageView?.image = UIImage(systemName: symbol)
        cell.imageView?.tintColor = tint == .secondaryLabel ? view.tintColor : tint
        cell.accessoryType = disclosure ? .disclosureIndicator : .none
        cell.selectionStyle = disclosure ? .default : .none
        return cell
    }

    private func subtitleCell(
        title: String,
        subtitle: String,
        symbol: String,
        disclosure: Bool
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: symbol)
        cell.imageView?.tintColor = view.tintColor
        cell.accessoryType = disclosure ? .disclosureIndicator : .none
        return cell
    }

    private func actionCell(_ title: String, symbol: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.textColor = view.tintColor
        cell.imageView?.image = UIImage(systemName: symbol)
        cell.imageView?.tintColor = view.tintColor
        return cell
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
