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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var keychain = Keychain(service: "com.scottmangiapane.Menu-Bar-2FA")
    var window: NSWindow!
    var statusBarItem: NSStatusItem!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
    }

    func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: NSImage.Name("lock"))
        let statusBarMenu = NSMenu()
        statusBarItem.menu = statusBarMenu

        statusBarMenu.addItem(
            withTitle: "Copy 2FA Token",
            action: #selector(AppDelegate.copyToken),
            keyEquivalent: "")

        statusBarMenu.addItem(.separator())

        statusBarMenu.addItem(
            withTitle: "Change Secret",
            action: #selector(AppDelegate.promptSecret),
            keyEquivalent: "")

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")

        let secret = keychain["base32"]
        if (secret == nil) {
            statusBarMenu.item(at: 0)?.action = nil
        }

        let timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(AppDelegate.updateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc func updateTimer()
    {
        let calendar = NSCalendar.current
        let components = calendar.dateComponents([.second], from: Date())
        let remaining = 30 - components.second! % 30
        statusBarItem.menu?.item(at: 0)?.title = "Copy 2FA Token (" + String(remaining) + ")"
    }

    @objc func copyToken() {
        let secret = keychain["base32"]
        guard let data = base32DecodeToData(secret ?? "") else { return }
        var textToCopy = "ERR_INVALID_TOTP_SECRET"
        if let totp = TOTP(secret: data) {
            textToCopy = totp.generate(time: Date()) ?? ""
        }
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(textToCopy, forType: .string)
    }

    @objc func promptSecret() -> Bool {
        let alert = NSAlert()
        alert.messageText = "What is your 2FA secret in base 32?"
        alert.informativeText = "This can be found in the otpauth URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let txt = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = txt
        let response: NSApplication.ModalResponse = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            keychain["base32"] = txt.stringValue
            statusBarItem.menu?.item(at: 0)?.action = #selector(AppDelegate.copyToken)
            return true
        }
        return false
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}
}
