//
//  AppDelegate.swift
//  Top Bar 2FA
//
//  Created by Scott Mangiapane on 4/17/20.
//  Copyright © 2020 Scott Mangiapane. All rights reserved.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var statusBarItem: NSStatusItem!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.prohibited)

        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.title = "🌯"
        let statusBarMenu = NSMenu(title: "Cap Status Bar Menu")
        statusBarItem.menu = statusBarMenu

        statusBarMenu.addItem(
            withTitle: "Order a burrito",
            action: #selector(AppDelegate.orderABurrito),
            keyEquivalent: "")

        statusBarMenu.addItem(
            withTitle: "Quit",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")
    }

    @objc func orderABurrito() {
        print("Ordering a burrito!")
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}
}
