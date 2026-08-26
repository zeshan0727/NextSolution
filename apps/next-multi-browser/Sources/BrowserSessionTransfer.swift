import CryptoKit
import Foundation
import Security
import UIKit
import UniformTypeIdentifiers

private struct BrowserSessionTransferProfile: Codable {
    let index: Int
    let displayName: String
    let cookieArchive: Data
}

private struct BrowserSessionTransferPayload: Codable {
    let formatVersion: Int
    let createdAt: Date
    let profiles: [BrowserSessionTransferProfile]
}

private struct BrowserSessionTransferEnvelope: Codable {
    let formatVersion: Int
    let salt: Data
    let sealedPayload: Data
}

private enum BrowserSessionTransferError: LocalizedError {
    case noSessions
    case invalidFile
    case wrongPassword
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noSessions:
            return "No profile cookies were found to export."
        case .invalidFile:
            return "This is not a valid Next Multi Browser session backup."
        case .wrongPassword:
            return "The password is incorrect or the backup is damaged."
        case .randomGenerationFailed:
            return "A secure encryption salt could not be generated."
        }
    }
}

final class BrowserSessionTransferController: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private let profileStore: BrowserProfileStore
    private var temporaryExportURL: URL?

    init(profileStore: BrowserProfileStore, presenter: UIViewController) {
        self.profileStore = profileStore
        self.presenter = presenter
    }

    func presentMenu(from barButtonItem: UIBarButtonItem) {
        guard let presenter else { return }
        let sheet = UIAlertController(
            title: "Transfer Logged Sessions",
            message: "Export profile cookies from the old device, then import the encrypted file on the new device.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Export Encrypted Sessions", style: .default) { [weak self] _ in
            self?.promptForExportPassword()
        })
        sheet.addAction(UIAlertAction(title: "Import Encrypted Sessions", style: .default) { [weak self] _ in
            self?.openImportPicker()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = barButtonItem
        presenter.present(sheet, animated: true)
    }

    private func promptForExportPassword() {
        guard let presenter else { return }
        let alert = UIAlertController(
            title: "Encrypt Session Backup",
            message: "Choose a password of at least 8 characters. You must enter the same password on the new device.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Backup password"
            field.isSecureTextEntry = true
            field.textContentType = .newPassword
        }
        alert.addTextField { field in
            field.placeholder = "Confirm password"
            field.isSecureTextEntry = true
            field.textContentType = .newPassword
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Export", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let fields = alert?.textFields,
                  fields.count == 2 else { return }
            let password = fields[0].text ?? ""
            let confirmation = fields[1].text ?? ""
            guard password.count >= 8, password == confirmation else {
                self.showAlert(
                    title: "Password Not Accepted",
                    message: "Use at least 8 characters and make sure both password fields match."
                )
                return
            }
            DispatchQueue.main.async {
                self.exportSessions(password: password)
            }
        })
        presenter.present(alert, animated: true)
    }

    private func exportSessions(password: String) {
        let progress = presentProgress(title: "Preparing Session Backup…")
        collectProfiles(index: 1, result: []) { [weak self, weak progress] profiles in
            guard let self else { return }
            do {
                guard !profiles.isEmpty else {
                    throw BrowserSessionTransferError.noSessions
                }
                let payload = BrowserSessionTransferPayload(
                    formatVersion: 1,
                    createdAt: Date(),
                    profiles: profiles
                )
                let payloadData = try JSONEncoder().encode(payload)
                let encrypted = try self.encrypt(payloadData, password: password)
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "NextMultiBrowser-Sessions-\(Int(Date().timeIntervalSince1970)).nmbsessions"
                )
                try encrypted.write(to: destination, options: [.atomic, .completeFileProtection])
                self.temporaryExportURL = destination
                progress?.dismiss(animated: true) {
                    self.presentShareSheet(fileURL: destination, profileCount: profiles.count)
                }
            } catch {
                progress?.dismiss(animated: true) {
                    self.showAlert(title: "Export Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func collectProfiles(
        index: Int,
        result: [BrowserSessionTransferProfile],
        completion: @escaping ([BrowserSessionTransferProfile]) -> Void
    ) {
        guard index <= BrowserProfileStore.profileCount else {
            completion(result)
            return
        }
        let session = profileStore.session(for: index)
        session.whenReady { [weak self] in
            guard let self else { return }
            session.getAllCookies { cookies in
                var updated = result
                if !cookies.isEmpty,
                   let archive = BrowserCookieArchive.serializedData(for: cookies) {
                    updated.append(BrowserSessionTransferProfile(
                        index: index,
                        displayName: self.profileStore.displayName(for: index),
                        cookieArchive: archive
                    ))
                }
                self.collectProfiles(index: index + 1, result: updated, completion: completion)
            }
        }
    }

    private func presentShareSheet(fileURL: URL, profileCount: Int) {
        guard let presenter else { return }
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = presenter.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 1,
            height: 1
        )
        controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
            if let url = self?.temporaryExportURL {
                try? FileManager.default.removeItem(at: url)
            }
            self?.temporaryExportURL = nil
        }
        presenter.present(controller, animated: true)
    }

    private func openImportPicker() {
        guard let presenter else { return }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else { return }
        promptForImportPassword(fileURL: url)
    }

    private func promptForImportPassword(fileURL: URL) {
        guard let presenter else { return }
        let alert = UIAlertController(
            title: "Unlock Session Backup",
            message: "Enter the password chosen on the old device.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Backup password"
            field.isSecureTextEntry = true
            field.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let password = alert?.textFields?.first?.text ?? ""
            DispatchQueue.main.async {
                self.prepareImport(fileURL: fileURL, password: password)
            }
        })
        presenter.present(alert, animated: true)
    }

    private func prepareImport(fileURL: URL, password: String) {
        do {
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            let encrypted = try Data(contentsOf: fileURL)
            let payloadData = try decrypt(encrypted, password: password)
            let payload = try JSONDecoder().decode(
                BrowserSessionTransferPayload.self,
                from: payloadData
            )
            guard payload.formatVersion == 1,
                  !payload.profiles.isEmpty,
                  payload.profiles.allSatisfy({
                      (1...BrowserProfileStore.profileCount).contains($0.index)
                  }) else {
                throw BrowserSessionTransferError.invalidFile
            }
            confirmImport(payload: payload)
        } catch let error as BrowserSessionTransferError {
            showAlert(title: "Import Failed", message: error.localizedDescription)
        } catch {
            showAlert(
                title: "Import Failed",
                message: BrowserSessionTransferError.wrongPassword.localizedDescription
            )
        }
    }

    private func confirmImport(payload: BrowserSessionTransferPayload) {
        guard let presenter else { return }
        let alert = UIAlertController(
            title: "Import \(payload.profiles.count) Logged Profile(s)?",
            message: "Cookies in matching browser profile numbers will be replaced. Other profiles remain unchanged.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { [weak self] _ in
            DispatchQueue.main.async {
                self?.importProfiles(payload.profiles)
            }
        })
        presenter.present(alert, animated: true)
    }

    private func importProfiles(_ profiles: [BrowserSessionTransferProfile]) {
        let sorted = profiles.sorted { $0.index < $1.index }
        let progress = presentProgress(title: "Importing Logged Sessions…")
        applyProfiles(sorted, position: 0) { [weak self, weak progress] importedCount in
            guard let self else { return }
            progress?.dismiss(animated: true) {
                self.showAlert(
                    title: "Session Import Complete",
                    message: "\(importedCount) profile(s) imported. Open each browser to verify the account. Some services may request sign-in verification on a new device."
                )
            }
        }
    }

    private func applyProfiles(
        _ profiles: [BrowserSessionTransferProfile],
        position: Int,
        completion: @escaping (Int) -> Void
    ) {
        guard position < profiles.count else {
            completion(profiles.count)
            return
        }
        let profile = profiles[position]
        let cookies = BrowserCookieArchive.cookies(from: profile.cookieArchive)
        let session = profileStore.session(for: profile.index)
        session.whenReady { [weak self] in
            guard let self else { return }
            session.replaceCookies(cookies) {
                self.profileStore.setDisplayName(profile.displayName, for: profile.index)
                self.applyProfiles(profiles, position: position + 1, completion: completion)
            }
        }
    }

    private func encrypt(_ data: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BrowserSessionTransferError.randomGenerationFailed
        }
        let key = derivedKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw BrowserSessionTransferError.invalidFile
        }
        return try JSONEncoder().encode(BrowserSessionTransferEnvelope(
            formatVersion: 1,
            salt: salt,
            sealedPayload: combined
        ))
    }

    private func decrypt(_ data: Data, password: String) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(
            BrowserSessionTransferEnvelope.self,
            from: data
        ), envelope.formatVersion == 1 else {
            throw BrowserSessionTransferError.invalidFile
        }
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
            return try AES.GCM.open(
                box,
                using: derivedKey(password: password, salt: envelope.salt)
            )
        } catch {
            throw BrowserSessionTransferError.wrongPassword
        }
    }

    private func derivedKey(password: String, salt: Data) -> SymmetricKey {
        var material = Data(password.utf8)
        material.append(salt)
        for _ in 0..<75_000 {
            material = Data(SHA256.hash(data: material))
        }
        return SymmetricKey(data: material)
    }

    @discardableResult
    private func presentProgress(title: String) -> UIAlertController? {
        guard let presenter else { return nil }
        let alert = UIAlertController(title: title, message: "\n", preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        alert.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -18)
        ])
        presenter.present(alert, animated: true)
        return alert
    }

    private func showAlert(title: String, message: String) {
        guard let presenter else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}
