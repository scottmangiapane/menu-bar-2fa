//
//  AppDelegate.swift
//  Top Bar 2FA
//
//  Created by Scott Mangiapane on 4/17/20.
//  Copyright © 2020 Scott Mangiapane. All rights reserved.
//

import Cocoa
import SwiftOTP
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var defaults = UserDefaults.standard
    var window: NSWindow!
    var statusBarItem: NSStatusItem!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
    }

    func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: NSImage.Name("go"))
        let statusBarMenu = NSMenu()
        statusBarItem.menu = statusBarMenu

        statusBarMenu.addItem(
            withTitle: "Copy 2FA token",
            action: #selector(AppDelegate.copyToken),
            keyEquivalent: "")

        statusBarMenu.addItem(.separator())

        statusBarMenu.addItem(
            withTitle: "Change secret",
            action: #selector(AppDelegate.promptSecret),
            keyEquivalent: "")

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")

        let secret = defaults.string(forKey: "base32")
        print("Using secret:", secret ?? "")
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
        statusBarItem.menu?.item(at: 0)?.title = "Copy 2FA token (" + String(remaining) + ")"
    }

    @objc func copyToken() {
        let base32 = defaults.string(forKey: "base32")
        guard let data = base32DecodeToData(base32 ?? "") else { return }
        if let totp = TOTP(secret: data) {
            let token = totp.generate(time: Date())
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.setString(token ?? "", forType: .string)
        } else {
            print("Invalid TOTP secret")
        }
    }

    @objc func promptSecret() -> Bool {
        let alert = NSAlert()
        alert.messageText = "What is your 2FA secret in base 32?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let txt = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = txt
        let response: NSApplication.ModalResponse = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            defaults.set(txt.stringValue, forKey: "base32")
            statusBarItem.menu?.item(at: 0)?.action = #selector(AppDelegate.copyToken)
            print("Writing secret to storage:", txt.stringValue)
            return true
        }
        return false
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}
}
