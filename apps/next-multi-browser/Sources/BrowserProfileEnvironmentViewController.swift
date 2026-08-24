import UIKit

final class BrowserProfileEnvironmentViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case randomize
        case device
        case userAgent
        case language
        case region
        case timezone
        case reset
    }

    private let profileIndex: Int
    private let profileStore: BrowserProfileStore

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
        title = "Environment"
        navigationItem.largeTitleDisplayMode = .never
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .randomize: return nil
        case .device: return "Phone & Viewport"
        case .userAgent: return "User Agent"
        case .language: return "Language & Locale"
        case .region: return "Region"
        case .timezone: return "Timezone"
        case .reset: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .randomize:
            return "Creates one matching device, user agent, language, region, and timezone combination for this profile only."
        case .device:
            return "Phone presets set WebKit mobile content mode and a CSS viewport hint for this profile. Tablet and desktop presets are no longer selectable."
        case .timezone:
            return "Language, locale, region, and timezone are applied to web content in this profile. Automatic follows the device."
        case .reset:
            return "Changing or resetting the environment does not clear cookies, logins, or website storage."
        default:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let environment = profileStore.environment(for: profileIndex)
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)

        switch Section(rawValue: indexPath.section)! {
        case .randomize:
            cell.textLabel?.text = "Randomize Environment"
            cell.textLabel?.textColor = view.tintColor
            cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
            cell.detailTextLabel?.text = "All settings"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: "shuffle")
            cell.imageView?.tintColor = view.tintColor
            cell.accessoryType = .none
            cell.accessibilityHint = "Randomizes this profile's testing environment without clearing its login or website data."
            return cell
        case .device:
            cell.textLabel?.text = environment.viewport.title
            cell.detailTextLabel?.text = environment.viewport.viewportDescription
            cell.imageView?.image = UIImage(systemName: deviceSymbol(environment.viewport))
        case .userAgent:
            cell.textLabel?.text = environment.userAgent.title
            cell.detailTextLabel?.text = environment.userAgent == .automatic ? "System WebKit" : "Preset"
            cell.imageView?.image = UIImage(systemName: "network")
        case .language:
            cell.textLabel?.text = environment.language.title
            cell.detailTextLabel?.text = environment.localeIdentifier
            cell.imageView?.image = UIImage(systemName: "character.book.closed.fill")
        case .region:
            cell.textLabel?.text = environment.region.title
            cell.detailTextLabel?.text = environment.region.regionCode ?? "Device"
            cell.imageView?.image = UIImage(systemName: "globe.americas.fill")
        case .timezone:
            cell.textLabel?.text = environment.timezone.title
            cell.detailTextLabel?.text = environment.timezone.identifier ?? "Device"
            cell.imageView?.image = UIImage(systemName: "clock.badge")
        case .reset:
            cell.textLabel?.text = "Reset to Automatic"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "arrow.counterclockwise")
            cell.imageView?.tintColor = .systemRed
            cell.accessoryType = .none
            return cell
        }

        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
        cell.detailTextLabel?.minimumScaleFactor = 0.7
        cell.imageView?.tintColor = view.tintColor
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .randomize:
            confirmRandomize()
        case .device:
            showViewportPicker()
        case .userAgent:
            showUserAgentPicker()
        case .language:
            showLanguagePicker()
        case .region:
            showRegionPicker()
        case .timezone:
            showTimezonePicker()
        case .reset:
            confirmReset()
        }
    }

    private func showViewportPicker() {
        let current = profileStore.environment(for: profileIndex).viewport
        let presets = BrowserViewportPreset.selectablePhoneCases
        showPicker(
            title: "Phone & Viewport",
            options: presets.map {
                BrowserProfilePickerOption(
                    title: $0.title,
                    subtitle: $0.viewportDescription,
                    isSelected: $0 == current
                )
            }
        ) { [weak self] selectedIndex in
            guard let self else { return }
            var environment = self.profileStore.environment(for: self.profileIndex)
            environment.viewport = presets[selectedIndex]
            self.profileStore.setEnvironment(environment, for: self.profileIndex)
            self.tableView.reloadData()
        }
    }

    private func showUserAgentPicker() {
        let current = profileStore.environment(for: profileIndex).userAgent
        let presets = BrowserUserAgentPreset.selectablePhoneCases
        showPicker(
            title: "Phone User Agent",
            options: presets.map {
                BrowserProfilePickerOption(
                    title: $0.title,
                    subtitle: $0 == .automatic ? "Use the current WebKit user agent" : "Compatibility preset",
                    isSelected: $0 == current
                )
            }
        ) { [weak self] selectedIndex in
            guard let self else { return }
            var environment = self.profileStore.environment(for: self.profileIndex)
            environment.userAgent = presets[selectedIndex]
            self.profileStore.setEnvironment(environment, for: self.profileIndex)
            self.tableView.reloadData()
        }
    }

    private func showLanguagePicker() {
        let current = profileStore.environment(for: profileIndex).language
        showPicker(
            title: "Language",
            options: BrowserLanguagePreset.allCases.map {
                BrowserProfilePickerOption(
                    title: $0.title,
                    subtitle: $0.languageCode ?? "Follow device",
                    isSelected: $0 == current
                )
            }
        ) { [weak self] selectedIndex in
            guard let self else { return }
            var environment = self.profileStore.environment(for: self.profileIndex)
            environment.language = BrowserLanguagePreset.allCases[selectedIndex]
            self.profileStore.setEnvironment(environment, for: self.profileIndex)
            self.tableView.reloadData()
        }
    }

    private func showRegionPicker() {
        let current = profileStore.environment(for: profileIndex).region
        showPicker(
            title: "Region",
            options: BrowserRegionPreset.allCases.map {
                BrowserProfilePickerOption(
                    title: $0.title,
                    subtitle: $0.regionCode ?? "Follow device",
                    isSelected: $0 == current
                )
            }
        ) { [weak self] selectedIndex in
            guard let self else { return }
            var environment = self.profileStore.environment(for: self.profileIndex)
            environment.region = BrowserRegionPreset.allCases[selectedIndex]
            self.profileStore.setEnvironment(environment, for: self.profileIndex)
            self.tableView.reloadData()
        }
    }

    private func showTimezonePicker() {
        let current = profileStore.environment(for: profileIndex).timezone
        showPicker(
            title: "Timezone",
            options: BrowserTimezonePreset.allCases.map {
                BrowserProfilePickerOption(
                    title: $0.title,
                    subtitle: $0.identifier ?? "Follow device",
                    isSelected: $0 == current
                )
            }
        ) { [weak self] selectedIndex in
            guard let self else { return }
            var environment = self.profileStore.environment(for: self.profileIndex)
            environment.timezone = BrowserTimezonePreset.allCases[selectedIndex]
            self.profileStore.setEnvironment(environment, for: self.profileIndex)
            self.tableView.reloadData()
        }
    }

    private func showPicker(
        title: String,
        options: [BrowserProfilePickerOption],
        onSelect: @escaping (Int) -> Void
    ) {
        let controller = BrowserProfileOptionPickerViewController(
            title: title,
            options: options,
            onSelect: onSelect
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func confirmReset() {
        let alert = UIAlertController(
            title: "Reset Environment?",
            message: "All environment choices for this profile return to Automatic. Login and website data remain untouched.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.profileStore.setEnvironment(.default, for: self.profileIndex)
            self.tableView.reloadData()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }

    private func confirmRandomize() {
        let profileName = profileStore.displayName(for: profileIndex)
        let alert = UIAlertController(
            title: "Randomize Environment?",
            message: "Device, user agent, language, region, and timezone will be randomized for \(profileName) only. Cookies, login, and website storage remain untouched.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Randomize", style: .default) { [weak self] _ in
            guard let self else { return }
            let current = self.profileStore.environment(for: self.profileIndex)
            let randomized = BrowserProfileEnvironment.randomized(excluding: current)
            self.profileStore.setEnvironment(randomized, for: self.profileIndex)
            UIView.transition(
                with: self.tableView,
                duration: 0.25,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    self.tableView.reloadData()
                },
                completion: nil
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        })
        present(alert, animated: true)
    }

    private func deviceSymbol(_ viewport: BrowserViewportPreset) -> String {
        switch viewport {
        case .automatic: return "rectangle.dashed"
        case .iPhoneSE, .iPhone8Plus, .iPhone13Mini, .iPhone11, .iPhone14,
             .iPhonePro, .iPhoneProMax, .iPhone16Pro, .iPhone16ProMax:
            return "iphone"
        case .iPodTouch: return "ipodtouch"
        case .iPadMini, .iPadAir, .iPadPro11, .iPadPro: return "ipad"
        case .pixel9Pro, .pixel9ProXL, .galaxyS25, .galaxyS25Ultra,
             .onePlus13, .xiaomi15Ultra:
            return "rectangle.portrait"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        }
    }
}
final class BrowserProfileAppearanceViewController: UITableViewController {
    private let profileIndex: Int
    private let profileStore: BrowserProfileStore

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
        title = "Icon & Color"
        navigationItem.largeTitleDisplayMode = .never
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? BrowserProfileIcon.allCases.count : BrowserProfileColor.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Profile Icon" : "Profile Color"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.section == 0 {
            let value = BrowserProfileIcon.allCases[indexPath.row]
            cell.textLabel?.text = value.title
            cell.imageView?.image = UIImage(systemName: value.symbolName)
            cell.imageView?.tintColor = profileStore.color(for: profileIndex).uiColor
            cell.accessoryType = value == profileStore.icon(for: profileIndex) ? .checkmark : .none
        } else {
            let value = BrowserProfileColor.allCases[indexPath.row]
            cell.textLabel?.text = value.title
            cell.imageView?.image = UIImage(systemName: "circle.fill")
            cell.imageView?.tintColor = value.uiColor
            cell.accessoryType = value == profileStore.color(for: profileIndex) ? .checkmark : .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            profileStore.setIcon(BrowserProfileIcon.allCases[indexPath.row], for: profileIndex)
        } else {
            profileStore.setColor(BrowserProfileColor.allCases[indexPath.row], for: profileIndex)
        }
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct BrowserProfilePickerOption {
    let title: String
    let subtitle: String?
    let isSelected: Bool
}

private final class BrowserProfileOptionPickerViewController: UITableViewController {
    private let screenTitle: String
    private let options: [BrowserProfilePickerOption]
    private let onSelect: (Int) -> Void

    init(
        title: String,
        options: [BrowserProfilePickerOption],
        onSelect: @escaping (Int) -> Void
    ) {
        self.screenTitle = title
        self.options = options
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = screenTitle
        navigationItem.largeTitleDisplayMode = .never
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let option = options[indexPath.row]
        let cell = UITableViewCell(
            style: option.subtitle == nil ? .default : .subtitle,
            reuseIdentifier: nil
        )
        cell.textLabel?.text = option.title
        cell.detailTextLabel?.text = option.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = option.isSelected ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(indexPath.row)
        UISelectionFeedbackGenerator().selectionChanged()
        navigationController?.popViewController(animated: true)
    }
}
