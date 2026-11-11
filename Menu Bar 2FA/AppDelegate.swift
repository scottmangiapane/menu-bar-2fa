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
import SwiftUI

private struct OTPAccount: Codable, Identifiable {
    let id: UUID
    var name: String
    var secret: String

    init(id: UUID = UUID(), name: String, secret: String) {
        self.id = id
        self.name = name
        self.secret = secret
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let keychain = Keychain(service: "com.scottmangiapane.Menu-Bar-2FA")
    private let accountsKey = "accounts"
    private let legacySecretKey = "base32"

    private var accounts: [OTPAccount] = []
    private var copyMenuItems: [UUID: NSMenuItem] = [:]
    private var accountStorageUnavailable = false

    var window: NSWindow!
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
                return
            }

            // Migrate the single-account format used by earlier versions.
            if let legacySecret = try keychain.get(legacySecretKey), !legacySecret.isEmpty {
                accounts = [OTPAccount(name: "Default", secret: legacySecret)]
                // Keep the legacy item as a backup. Newer versions read `accounts` first.
                _ = saveAccounts()
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
        copyMenuItems.removeAll()

        if accounts.isEmpty {
            let emptyItem = NSMenuItem(title: "No Accounts Configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            statusBarMenu.addItem(emptyItem)
        } else {
            for account in accounts {
                let accountItem = NSMenuItem(title: account.name, action: nil, keyEquivalent: "")
                let accountMenu = NSMenu()

                let copyItem = NSMenuItem(
                    title: copyTokenTitle,
                    action: #selector(copyToken(_:)),
                    keyEquivalent: ""
                )
                copyItem.target = self
                copyItem.representedObject = account.id.uuidString
                accountMenu.addItem(copyItem)
                copyMenuItems[account.id] = copyItem

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

    private var copyTokenTitle: String {
        "Copy 2FA Token (\(secondsUntilNextToken))"
    }

    private var secondsUntilNextToken: Int {
        let elapsedSeconds = Int(Date().timeIntervalSince1970) % 30
        return 30 - elapsedSeconds
    }

    @objc private func updateTimer() {
        let title = copyTokenTitle
        for menuItem in copyMenuItems.values {
            menuItem.title = title
        }
    }

    @objc private func copyToken(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let account = accounts.first(where: { $0.id == id }),
              let data = base32DecodeToData(account.secret),
              let totp = TOTP(secret: data),
              let token = totp.generate(time: Date()) else {
            showError(
                title: "Couldn't Generate Token",
                message: "This account's secret is invalid. Edit the account and check its Base32 secret."
            )
            return
        }

        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(token, forType: .string)
    }

    @objc private func addAccount() {
        guard !accountStorageUnavailable,
              let account = promptForAccount() else { return }
        accounts.append(account)
        guard saveAccounts() else {
            accounts.removeAll { $0.id == account.id }
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
        alert.informativeText = "Enter a name and the account's Base32 secret."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 64))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 36, width: 280, height: 24))
        nameField.placeholderString = "Account name (e.g. GitHub – alice)"
        nameField.stringValue = existingAccount?.name ?? ""

        let secretField = NSSecureTextField(frame: NSRect(x: 0, y: 4, width: 280, height: 24))
        secretField.placeholderString = "Base32 secret"
        secretField.stringValue = existingAccount?.secret ?? ""

        accessoryView.addSubview(nameField)
        accessoryView.addSubview(secretField)
        alert.accessoryView = accessoryView
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let nameInput = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = normalizedSecret(from: secretField.stringValue)
        guard !secret.isEmpty,
              let secretData = base32DecodeToData(secret),
              TOTP(secret: secretData) != nil else {
            showError(
                title: "Invalid 2FA Secret",
                message: "Enter a valid Base32 secret. The account was not saved."
            )
            return nil
        }

        let name: String
        if !nameInput.isEmpty {
            name = nameInput
        } else if let existingAccount {
            name = existingAccount.name
        } else {
            name = "Account \(accounts.count + 1)"
        }

        return OTPAccount(
            id: existingAccount?.id ?? UUID(),
            name: name,
            secret: secret
        )
    }

    private func normalizedSecret(from input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
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

    func applicationWillTerminate(_ aNotification: Notification) {}
}
