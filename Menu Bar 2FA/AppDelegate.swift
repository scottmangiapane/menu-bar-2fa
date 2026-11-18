//
//  AppDelegate.swift
//  Menu Bar 2FA
//
//  Created by Scott Mangiapane on 4/17/20.
//  Copyright © 2020 Scott Mangiapane. All rights reserved.
//

import Cocoa
import KeychainAccess
import SwiftOTP
import Vision
import UniformTypeIdentifiers

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let keychain = Keychain(service: "com.scottmangiapane.Menu-Bar-2FA")
    private let accountsKey = "accounts"
    private let legacySecretKey = "base32"

    private var accounts: [OTPAccount] = []
    private var copyMenuItems: [UUID: NSMenuItem] = [:]
    private var accountStorageUnavailable = false
    private weak var activeNameField: NSTextField?
    private weak var activeSecretField: NSSecureTextField?
    private weak var activeImportStatusLabel: NSTextField?
    private var activeTOTPConfiguration: TOTPConfiguration?

    var statusBarItem: NSStatusItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadAccounts()
        setupStatusBar()
    }

    private func loadAccounts() {
        do {
            // Prefer the multi-account format whenever it exists.
            if let storedAccounts = try keychain.get(accountsKey) {
                guard let data = storedAccounts.data(using: .utf8),
                      let decodedAccounts = try? JSONDecoder().decode([OTPAccount].self, from: data) else {
                    accounts = []
                    accountStorageUnavailable = true
                    showError(
                        title: "Couldn't Load Accounts",
                        message: "The saved account data in the Keychain couldn't be read. The stored data has been left untouched."
                    )
                    return
                }

                accounts = decodedAccounts
                // The collection is now authoritative; remove any obsolete single-account value.
                try? keychain.remove(legacySecretKey)
                return
            }

            // Migrate the single-account format used by earlier versions.
            if let legacySecret = try keychain.get(legacySecretKey), !legacySecret.isEmpty {
                accounts = [OTPAccount(name: "Default", secret: legacySecret)]
                if saveAccounts() {
                    try? keychain.remove(legacySecretKey)
                }
            }
        } catch {
            accounts = []
            accountStorageUnavailable = true
            showError(title: "Couldn't Access Keychain", message: error.localizedDescription)
        }
    }

    @discardableResult
    private func saveAccounts() -> Bool {
        do {
            let data = try JSONEncoder().encode(accounts)
            guard let json = String(data: data, encoding: .utf8) else {
                accountStorageUnavailable = true
                showError(title: "Couldn't Save Accounts", message: "The account data couldn't be encoded.")
                return false
            }
            try keychain.set(json, key: accountsKey)
            return true
        } catch {
            accountStorageUnavailable = true
            showError(title: "Couldn't Save Accounts", message: error.localizedDescription)
            return false
        }
    }

    private func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: NSImage.Name("lock"))

        rebuildMenu()

        let timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(updateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rebuildMenu() {
        let statusBarMenu = NSMenu()
        statusBarMenu.autoenablesItems = false
        copyMenuItems.removeAll()

        if accounts.isEmpty {
            let emptyItem = NSMenuItem(title: "No Accounts Configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            statusBarMenu.addItem(emptyItem)
        } else {
            for account in accounts {
                let accountItem = NSMenuItem(title: account.name, action: nil, keyEquivalent: "")
                let accountMenu = NSMenu()
                accountMenu.autoenablesItems = false

                let copyItem = NSMenuItem(
                    title: copyTokenTitle(for: account),
                    action: #selector(copyToken(_:)),
                    keyEquivalent: ""
                )
                copyItem.target = self
                copyItem.representedObject = account.id.uuidString
                accountMenu.addItem(copyItem)
                copyMenuItems[account.id] = copyItem

                accountMenu.addItem(.separator())

                let editItem = NSMenuItem(
                    title: "Edit Account…",
                    action: #selector(editAccount(_:)),
                    keyEquivalent: ""
                )
                editItem.target = self
                editItem.representedObject = account.id.uuidString
                editItem.isEnabled = !accountStorageUnavailable
                accountMenu.addItem(editItem)

                let removeItem = NSMenuItem(
                    title: "Remove Account…",
                    action: #selector(removeAccount(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = account.id.uuidString
                removeItem.isEnabled = !accountStorageUnavailable
                accountMenu.addItem(removeItem)

                accountMenu.addItem(.separator())

                let moveUpItem = NSMenuItem(
                    title: "Move Up",
                    action: #selector(moveAccountUp(_:)),
                    keyEquivalent: ""
                )
                moveUpItem.target = self
                moveUpItem.representedObject = account.id.uuidString
                moveUpItem.isEnabled = !accountStorageUnavailable && accounts.first?.id != account.id
                accountMenu.addItem(moveUpItem)

                let moveDownItem = NSMenuItem(
                    title: "Move Down",
                    action: #selector(moveAccountDown(_:)),
                    keyEquivalent: ""
                )
                moveDownItem.target = self
                moveDownItem.representedObject = account.id.uuidString
                moveDownItem.isEnabled = !accountStorageUnavailable && accounts.last?.id != account.id
                accountMenu.addItem(moveDownItem)

                accountItem.submenu = accountMenu
                statusBarMenu.addItem(accountItem)
            }
        }
        statusBarMenu.addItem(.separator())

        let addItem = NSMenuItem(
            title: "Add Account…",
            action: #selector(addAccount),
            keyEquivalent: ""
        )
        addItem.target = self
        addItem.isEnabled = !accountStorageUnavailable
        statusBarMenu.addItem(addItem)

        statusBarMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        statusBarMenu.addItem(quitItem)

        statusBarItem.menu = statusBarMenu
        updateTimer()
    }

    private func copyTokenTitle(for account: OTPAccount) -> String {
        "Copy Code (\(secondsUntilNextToken(period: account.configuration.period))s)"
    }

    private func secondsUntilNextToken(period: Int) -> Int {
        guard period > 0 else { return 0 }
        let elapsedSeconds = Int(Date().timeIntervalSince1970) % period
        return period - elapsedSeconds
    }

    @objc private func updateTimer() {
        for account in accounts {
            copyMenuItems[account.id]?.title = copyTokenTitle(for: account)
        }
    }

    @objc private func copyToken(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let account = accounts.first(where: { $0.id == id }),
              let data = base32DecodeToData(account.secret),
              let totp = TOTP(
                  secret: data,
                  digits: account.configuration.digits,
                  timeInterval: account.configuration.period,
                  algorithm: account.configuration.algorithm.swiftOTPAlgorithm
              ),
              let token = totp.generate(time: Date()) else {
            showError(
                title: "Couldn't Generate Token",
                message: "This account's setup is invalid. Edit the account and check its setup information."
            )
            return
        }

        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        guard pasteBoard.setString(token, forType: .string) else {
            showError(title: "Couldn't Copy Token", message: "The token was generated, but macOS couldn't write it to the clipboard.")
            return
        }
    }

    @objc private func addAccount() {
        guard !accountStorageUnavailable,
              let account = promptForAccount() else { return }
        accounts.append(account)
        guard saveAccounts() else {
            accounts.removeAll { $0.id == account.id }
            rebuildMenu()
            return
        }
        rebuildMenu()
    }

    @objc private func editAccount(_ sender: NSMenuItem) {
        guard !accountStorageUnavailable,
              let accountID = accountID(from: sender),
              let accountIndex = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        guard let updatedAccount = promptForAccount(existingAccount: accounts[accountIndex]) else { return }
        let originalAccount = accounts[accountIndex]
        accounts[accountIndex] = updatedAccount
        guard saveAccounts() else {
            accounts[accountIndex] = originalAccount
            rebuildMenu()
            return
        }
        rebuildMenu()
    }

    @objc private func removeAccount(_ sender: NSMenuItem) {
        guard !accountStorageUnavailable,
              let accountID = accountID(from: sender),
              let account = accounts.first(where: { $0.id == accountID }) else { return }

        let alert = NSAlert()
        alert.messageText = "Remove \(account.name)?"
        alert.informativeText = "This will delete the account's stored 2FA secret."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn,
              let accountIndex = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let removedAccount = accounts.remove(at: accountIndex)
        guard saveAccounts() else {
            accounts.insert(removedAccount, at: accountIndex)
            rebuildMenu()
            return
        }
        rebuildMenu()
    }

    @objc private func moveAccountUp(_ sender: NSMenuItem) {
        moveAccount(sender, offset: -1)
    }

    @objc private func moveAccountDown(_ sender: NSMenuItem) {
        moveAccount(sender, offset: 1)
    }

    private func moveAccount(_ sender: NSMenuItem, offset: Int) {
        guard !accountStorageUnavailable,
              let accountID = accountID(from: sender),
              let currentIndex = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        let destinationIndex = currentIndex + offset
        guard accounts.indices.contains(destinationIndex) else { return }

        accounts.swapAt(currentIndex, destinationIndex)
        guard saveAccounts() else {
            // Restore the in-memory order if Keychain persistence fails.
            accounts.swapAt(currentIndex, destinationIndex)
            rebuildMenu()
            return
        }

        rebuildMenu()
    }

    private func accountID(from sender: NSMenuItem) -> UUID? {
        guard let idString = sender.representedObject as? String else { return nil }
        return UUID(uuidString: idString)
    }

    private func promptForAccount(existingAccount: OTPAccount? = nil) -> OTPAccount? {
        let alert = NSAlert()
        alert.messageText = existingAccount == nil ? "Add 2FA Account" : "Edit 2FA Account"
        alert.informativeText = "Paste an authenticator setup link or secret key, or import a QR code image. Any settings included in a setup link or QR code are kept, while a key entered on its own uses the standard settings: SHA-1, 6 digits, and a new code every 30 seconds."
        alert.alertStyle = .informational
        alert.addButton(withTitle: existingAccount == nil ? "Add Account" : "Save Changes")
        alert.addButton(withTitle: "Cancel")

        let accessoryWidth: CGFloat = 380
        let accessoryHeight: CGFloat = 300
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: accessoryHeight))

        let setupHeading = NSTextField(labelWithString: "1. Add your setup information")
        setupHeading.frame = NSRect(x: 0, y: 274, width: accessoryWidth, height: 18)
        setupHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let pasteButton = NSButton(
            title: "Paste from Clipboard",
            target: self,
            action: #selector(pasteSetupInformation(_:))
        )
        pasteButton.frame = NSRect(x: 0, y: 235, width: accessoryWidth, height: 30)
        pasteButton.bezelStyle = .rounded
        pasteButton.controlSize = .large

        let pasteDescription = NSTextField(labelWithString: "Accepts a QR code image, setup URL, or Base32 secret key.")
        pasteDescription.frame = NSRect(x: 0, y: 215, width: accessoryWidth, height: 16)
        pasteDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pasteDescription.textColor = .secondaryLabelColor

        let importFileButton = NSButton(
            title: "Choose QR Code Image…",
            target: self,
            action: #selector(importQRCodeFromFile(_:))
        )
        importFileButton.frame = NSRect(x: 0, y: 175, width: accessoryWidth, height: 30)
        importFileButton.bezelStyle = .rounded
        importFileButton.controlSize = .large

        let importDescription = NSTextField(labelWithString: "Import a QR code image saved on this Mac.")
        importDescription.frame = NSRect(x: 0, y: 155, width: accessoryWidth, height: 16)
        importDescription.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        importDescription.textColor = .secondaryLabelColor

        let separator = NSBox(frame: NSRect(x: 0, y: 142, width: accessoryWidth, height: 1))
        separator.boxType = .separator

        let manualHeading = NSTextField(labelWithString: "Or enter a Base32 secret key")
        manualHeading.frame = NSRect(x: 0, y: 118, width: accessoryWidth, height: 18)
        manualHeading.font = .systemFont(ofSize: NSFont.systemFontSize)

        let manualEntryButton = NSButton(
            title: "Enter setup key manually…",
            target: self,
            action: #selector(revealManualSecretField(_:))
        )
        manualEntryButton.frame = NSRect(x: 0, y: 86, width: accessoryWidth, height: 26)
        manualEntryButton.bezelStyle = .rounded

        let secretField = NSSecureTextField(frame: NSRect(x: 0, y: 86, width: accessoryWidth, height: 26))
        secretField.placeholderString = "Base32 secret key"
        secretField.stringValue = existingAccount?.secret ?? ""
        secretField.isHidden = true

        let statusLabel = NSTextField(labelWithString: existingAccount == nil
            ? "No setup information imported yet"
            : "Existing setup information will be kept")
        statusLabel.frame = NSRect(x: 0, y: 64, width: accessoryWidth, height: 16)
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let nameHeading = NSTextField(labelWithString: "2. Name your account (optional)")
        nameHeading.frame = NSRect(x: 0, y: 34, width: accessoryWidth, height: 18)
        nameHeading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let nameField = NSTextField(frame: NSRect(x: 0, y: 4, width: accessoryWidth, height: 24))
        nameField.placeholderString = "e.g. GitHub – alice"
        nameField.stringValue = existingAccount?.name ?? ""

        accessoryView.addSubview(setupHeading)
        accessoryView.addSubview(pasteButton)
        accessoryView.addSubview(pasteDescription)
        accessoryView.addSubview(importFileButton)
        accessoryView.addSubview(importDescription)
        accessoryView.addSubview(separator)
        accessoryView.addSubview(manualHeading)
        accessoryView.addSubview(manualEntryButton)
        accessoryView.addSubview(secretField)
        accessoryView.addSubview(statusLabel)
        accessoryView.addSubview(nameHeading)
        accessoryView.addSubview(nameField)
        alert.accessoryView = accessoryView

        activeNameField = nameField
        activeSecretField = secretField
        activeImportStatusLabel = statusLabel
        activeTOTPConfiguration = existingAccount?.configuration ?? .standard
        defer {
            activeNameField = nil
            activeSecretField = nil
            activeImportStatusLabel = nil
            activeTOTPConfiguration = nil
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let nameInput = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = TOTPProvisioning.normalizedSecret(from: secretField.stringValue)
        guard !secret.isEmpty,
              let secretData = base32DecodeToData(secret),
              let configuration = activeTOTPConfiguration,
              TOTP(
                  secret: secretData,
                  digits: configuration.digits,
                  timeInterval: configuration.period,
                  algorithm: configuration.algorithm.swiftOTPAlgorithm
              ) != nil else {
            showError(
                title: "Invalid 2FA Setup",
                message: "Import a supported TOTP QR code, paste a setup URL, or enter a valid setup key. The account was not saved."
            )
            return nil
        }

        let name: String
        if !nameInput.isEmpty {
            name = nameInput
        } else if let existingAccount {
            name = existingAccount.name
        } else {
            name = nextDefaultAccountName()
        }

        return OTPAccount(
            id: existingAccount?.id ?? UUID(),
            name: name,
            secret: secret,
            configuration: activeTOTPConfiguration ?? .standard
        )
    }

    private func nextDefaultAccountName() -> String {
        let highestExistingNumber = accounts.compactMap { account -> Int? in
            let prefix = "Account "
            guard account.name.hasPrefix(prefix),
                  let number = Int(account.name.dropFirst(prefix.count)),
                  number > 0 else {
                return nil
            }
            return number
        }.max() ?? 0

        return "Account \(highestExistingNumber + 1)"
    }

    @objc private func revealManualSecretField(_ sender: NSButton) {
        sender.isHidden = true
        // Revealing the key field must not discard settings from an imported URL or existing account.
        guard let secretField = activeSecretField else { return }
        secretField.isHidden = false
        activeImportStatusLabel?.stringValue = "Enter a Base32 key below. The current TOTP settings are retained."
        activeImportStatusLabel?.textColor = .secondaryLabelColor
        secretField.window?.makeFirstResponder(secretField)
    }

    @objc private func importQRCodeFromFile(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "Choose a 2FA QR Code Image"
        panel.prompt = "Import QR Code"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let imageData = try Data(contentsOf: url)
            _ = importQRCode(from: imageData)
        } catch {
            showError(title: "Couldn't Open Image", message: error.localizedDescription)
        }
    }

    @objc private func pasteSetupInformation(_ sender: NSButton) {
        let pasteboard = NSPasteboard.general

        // Screenshots copied with the macOS screenshot tool are commonly available as TIFF or PNG.
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            _ = importQRCode(from: imageData)
            return
        }

        if let string = pasteboard.string(forType: .string) {
            _ = importSetupValue(string)
            return
        }

        showError(
            title: "Nothing to Import",
            message: "The clipboard doesn't contain a readable TOTP QR code, setup URL, or setup key."
        )
    }

    @discardableResult
    private func importQRCode(from imageData: Data) -> Bool {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        do {
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            guard !observations.isEmpty else {
                showError(
                    title: "Couldn't Read QR Code",
                    message: "No QR code was found in that image. Try a clearer screenshot or another image."
                )
                return false
            }
            guard observations.count == 1 else {
                showError(
                    title: "Couldn't Read QR Code",
                    message: "More than one QR code was found. Crop the image so it contains only the intended code."
                )
                return false
            }
            guard let payload = observations.first?.payloadStringValue else {
                showError(
                    title: "Couldn't Read QR Code",
                    message: "The QR code couldn't be decoded as text. Try another image."
                )
                return false
            }

            return importSetupValue(payload)
        } catch {
            showError(title: "Couldn't Read QR Code", message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private func importSetupValue(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret: String
        let issuer: String?

        if trimmedValue.lowercased().hasPrefix("otpauth://") {
            guard let provisioningInfo = TOTPProvisioning.parse(trimmedValue) else {
                showError(
                    title: "Unsupported Setup Code",
                    message: "This setup URL isn't a supported TOTP configuration. Menu Bar 2FA supports SHA-1, SHA-256, or SHA-512; 6- or 8-digit codes; and any positive time period."
                )
                return false
            }

            secret = provisioningInfo.secret
            issuer = provisioningInfo.issuer
            activeTOTPConfiguration = provisioningInfo.configuration
        } else {
            secret = TOTPProvisioning.normalizedSecret(from: trimmedValue)
            issuer = nil
            // A raw setup key carries no TOTP parameters, so use the standard defaults.
            activeTOTPConfiguration = .standard
        }

        guard let secretData = base32DecodeToData(secret) else {
            showError(
                title: "Invalid Setup Key",
                message: "The imported value isn't a valid TOTP setup key."
            )
            return false
        }

        let configuration = activeTOTPConfiguration ?? .standard
        guard TOTP(
            secret: secretData,
            digits: configuration.digits,
            timeInterval: configuration.period,
            algorithm: configuration.algorithm.swiftOTPAlgorithm
        ) != nil else {
            showError(
                title: "Invalid TOTP Configuration",
                message: "The setup information contains unsupported TOTP settings."
            )
            return false
        }

        activeSecretField?.stringValue = secret
        activeImportStatusLabel?.stringValue = "Setup code imported"
        activeImportStatusLabel?.textColor = .systemGreen
        if let issuer,
           activeNameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            activeNameField?.stringValue = issuer
        }
        return true
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
}
