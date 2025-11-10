import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!
  private var debugPanelWindow: NSWindow?
  private var debugMenuItem: NSMenuItem?

  func applicationDidFinishLaunching(_: Notification) {
    // Create the SwiftUI view
    let contentView = RemoteControlView()

    // Create the window and set the content view
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.center()
    window.setFrameAutosaveName("Main Window")
    window.contentView = NSHostingView(rootView: contentView)
    window.title = "CuePad - Apple TV Remote"
    window.makeKeyAndOrderFront(nil)
    window.delegate = self

    setupDebugMenu()
  }

  func applicationWillTerminate(_: Notification) {
    // Insert code here to tear down your application
  }

  func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
    return true
  }

  // MARK: - Debug Panel

  private func setupDebugMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }

    let toggleItem = NSMenuItem(
      title: "Show Debug Panel",
      action: #selector(toggleDebugPanel(_:)),
      keyEquivalent: "d"
    )
    toggleItem.keyEquivalentModifierMask = [.command, .option]
    toggleItem.target = self

    if let debugMenu = mainMenu.item(withTitle: "Debug")?.submenu {
      debugMenu.addItem(NSMenuItem.separator())
      debugMenu.addItem(toggleItem)
    } else {
      let debugSubMenu = NSMenu(title: "Debug")
      debugSubMenu.addItem(toggleItem)

      let debugMenuItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
      debugMenuItem.submenu = debugSubMenu
      mainMenu.addItem(debugMenuItem)
    }

    debugMenuItem = toggleItem
  }

  @objc private func toggleDebugPanel(_ sender: NSMenuItem) {
    if let panel = debugPanelWindow {
      panel.close()
      return
    }

    let panel = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    panel.title = "CuePad Debug Panel"
    panel.isReleasedWhenClosed = false
    panel.center()
    panel.contentView = NSHostingView(rootView: DebugPanelView())
    panel.delegate = self
    panel.minSize = NSSize(width: 700, height: 500)
    panel.makeKeyAndOrderFront(nil)

    debugPanelWindow = panel
    updateDebugMenuItem(showing: true)
  }

  private func updateDebugMenuItem(showing: Bool) {
    debugMenuItem?.title = showing ? "Hide Debug Panel" : "Show Debug Panel"
    debugMenuItem?.state = showing ? .on : .off
  }

  func windowWillClose(_ notification: Notification) {
    guard
      let closingWindow = notification.object as? NSWindow,
      closingWindow == debugPanelWindow
    else { return }

    debugPanelWindow = nil
    updateDebugMenuItem(showing: false)
  }
}
