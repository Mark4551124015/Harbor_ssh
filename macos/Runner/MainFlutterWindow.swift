import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var commandChannel: FlutterMethodChannel?

  @objc private func performHarborCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    commandChannel?.invokeMethod(command, arguments: nil)
  }

  private func installCommandMenu() {
    guard let menu = NSApp.mainMenu else { return }
    func item(_ title: String, _ key: String, _ command: String,
              modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: #selector(performHarborCommand(_:)),
                            keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = self
      item.representedObject = command
      return item
    }
    if let appMenu = menu.items.first?.submenu,
       let preferences = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
      preferences.title = "Settings…"
      preferences.target = self
      preferences.action = #selector(performHarborCommand(_:))
      preferences.representedObject = "settings"
    }
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(item("New Connection", "n", "newConnection"))
    fileMenu.addItem(item("Save SSH Configuration", "s", "save"))
    fileMenu.addItem(.separator())
    // Route through AppKit's responder chain, matching the standard close button.
    fileMenu.addItem(NSMenuItem(title: "Close Window",
      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    file.submenu = fileMenu
    menu.insertItem(file, at: 1)
    let navigateMenu = NSMenu(title: "Navigate")
    navigateMenu.addItem(item("Quick Connect…", "k", "quickConnect"))
    navigateMenu.addItem(item("Search…", "f", "search"))
    navigateMenu.addItem(item("Search… (Control-F)", "f", "search",
                              modifiers: [.control]))
    let navigate = NSMenuItem(title: "Navigate", action: nil, keyEquivalent: "")
    navigate.submenu = navigateMenu
    menu.insertItem(navigate, at: 3)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 960, height: 680)
    // Keep the initial window at or above the minimum size so resizing never
    // snaps it up unexpectedly.
    let defaultSize = NSSize(width: 1040, height: 720)
    if self.frame.width < self.minSize.width ||
      self.frame.height < self.minSize.height {
      self.setContentSize(defaultSize)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(name: "harbor/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "applicationInfo" {
        result([
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
          "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        ])
        return
      }
      guard call.method == "pickPrivateKey" else { result(FlutterMethodNotImplemented); return }
      let panel = NSOpenPanel()
      panel.title = "Import SSH private key"
      panel.prompt = "Import"
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.showsHiddenFiles = true
      panel.beginSheetModal(for: self) { response in
        result(response == .OK ? panel.url?.path : nil)
      }
    }

    commandChannel = FlutterMethodChannel(name: "harbor/commands",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    super.awakeFromNib()
    installCommandMenu()
    self.title = "Harbor SSH"
    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }
  }
}
