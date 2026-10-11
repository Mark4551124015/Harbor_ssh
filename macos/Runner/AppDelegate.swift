import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication,
                                             hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      sender.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  private var terminating = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminating { return .terminateLater }
    guard let window = sender.windows.first(where: { $0 is MainFlutterWindow })
      as? MainFlutterWindow else { return .terminateNow }
    terminating = true
    window.shutdownConnections {
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
