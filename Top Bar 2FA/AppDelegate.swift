//
//  AppDelegate.swift
//  Top Bar 2FA
//
//  Created by Scott Mangiapane on 4/17/20.
//  Copyright © 2020 Scott Mangiapane. All rights reserved.
//

import Cocoa
import SwiftOTP

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var statusBarItem: NSStatusItem!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        setupStatusBar()
    }

    func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.title = "🌯"
        let statusBarMenu = NSMenu()
        statusBarItem.menu = statusBarMenu

        statusBarMenu.addItem(
            withTitle: "Copy 2FA token",
            action: #selector(AppDelegate.copyToken),
            keyEquivalent: "")

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")
    }

    func dialogOKCancel() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enter your Google Authenticator secret"
        alert.informativeText = "Enter your Google Authenticator secret"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc func copyToken() {
        guard let data = base32DecodeToData("(put your token here)") else { return }
        if let totp = TOTP(secret: data) {
            let token = totp.generate(time: Date())
            print(token as Any)
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.setString(token ?? "", forType: .string)
            let answer = dialogOKCancel()
            print(answer)
        } else {
            print("Invalid token URL")
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}
}
