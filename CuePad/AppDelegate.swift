import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

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
}
