import Cocoa
import CFNetwork
import QuartzCore
import FlutterMacOS

private final class HarborPACResult {
  var proxies: [[String: Any]] = []
  var finished = false
  var failed = false
}

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var commandChannel: FlutterMethodChannel?
  private var launchCover: NSView?

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep the Flutter engine and its owned SSH processes alive until Cmd-Q.
    sender.orderOut(nil)
    return false
  }

  private func installLaunchCover() {
    guard let content = contentView else { return }
    let cover = NSView(frame: content.bounds)
    cover.autoresizingMask = [.width, .height]
    cover.wantsLayer = true
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    cover.layer?.backgroundColor = (dark
      ? NSColor(srgbRed: 17/255, green: 27/255, blue: 40/255, alpha: 1)
      : NSColor(srgbRed: 245/255, green: 242/255, blue: 237/255, alpha: 1)).cgColor
    let logo = NSImageView()
    logo.image = NSApp.applicationIconImage
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(logo)
    NSLayoutConstraint.activate([
      logo.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      logo.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      logo.widthAnchor.constraint(equalToConstant: 160),
      logo.heightAnchor.constraint(equalToConstant: 160)
    ])
    content.addSubview(cover)
    launchCover = cover
  }

  private func revealFlutter() {
    guard let cover = launchCover else { return }
    launchCover = nil
    // Keep one native logo throughout startup; swapping to a Flutter-drawn
    // icon changes the visible size because the app icon includes padding.
    cover.layer?.backgroundColor = NSColor.clear.cgColor
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.5
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cover.animator().alphaValue = 0
      }, completionHandler: { cover.removeFromSuperview() })
    }
  }

  func shutdownConnections(completion: @escaping () -> Void) {
    guard let channel = commandChannel else { completion(); return }
    channel.invokeMethod("shutdown", arguments: nil) { _ in completion() }
  }

  private func systemProxy(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let value = args["url"] as? String,
      let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") else {
      result(FlutterError(code: "proxy", message: "Invalid proxy destination.", details: nil)); return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
        DispatchQueue.main.async { result(["type": "direct", "configured": false]) }; return
      }
      let dictionary = settings as NSDictionary
      let configured = ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"]
        .contains { (dictionary[$0] as? NSNumber)?.boolValue == true }
      var proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as? [[String: Any]] ?? []
      if let first = proxies.first,
        first[kCFProxyTypeKey as String] as? String == kCFProxyTypeAutoConfigurationURL as String,
        let pacURL = first[kCFProxyAutoConfigurationURLKey as String] as? URL {
        let box = HarborPACResult()
        var context = CFStreamClientContext(version: 0,
          info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let source = CFNetworkExecuteProxyAutoConfigurationURL(pacURL as CFURL, url as CFURL,
          { info, list, error in
            let box = Unmanaged<HarborPACResult>.fromOpaque(info).takeUnretainedValue()
            box.proxies = list as? [[String: Any]] ?? []
            box.failed = error != nil
            box.finished = true
          }, &context)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        let deadline = Date().addingTimeInterval(10)
        while !box.finished && Date() < deadline {
          CFRunLoopRunInMode(.defaultMode, 0.1, true)
        }
        CFRunLoopSourceInvalidate(source)
        guard box.finished && !box.failed else {
          DispatchQueue.main.async { result(FlutterError(code: "proxy",
            message: "Could not resolve the system proxy script. Check Proxy settings.", details: nil)) }; return
        }
        proxies = box.proxies
      }
      guard let first = proxies.first else {
        DispatchQueue.main.async { result(["type": "direct", "configured": configured]) }; return
      }
      let type = first[kCFProxyTypeKey as String] as? String ?? ""
      if type == kCFProxyTypeNone as String {
        DispatchQueue.main.async { result(["type": "direct", "configured": configured]) }; return
      }
      guard [kCFProxyTypeHTTP as String, kCFProxyTypeSOCKS as String, kCFProxyTypeHTTPS as String].contains(type),
        let host = first[kCFProxyHostNameKey as String] as? String,
        let port = first[kCFProxyPortNumberKey as String] as? NSNumber else {
        DispatchQueue.main.async { result(FlutterError(code: "proxy", message: "Unsupported system proxy.", details: nil)) }; return
      }
      DispatchQueue.main.async { result(["type": type == kCFProxyTypeSOCKS as String ? "socks" : "http",
        "host": host, "port": port.intValue, "configured": true]) }
    }
  }

  private func installUpdate(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
      let path = values["path"] as? String, let build = values["build"] as? Int else {
      result(FlutterError(code: "update", message: "Invalid update request.", details: nil)); return
    }
    let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
    // Read-only disk images and App Translocation cannot be updated in place.
    guard !target.path.contains("/AppTranslocation/"),
      !target.path.hasPrefix("/Volumes/"),
      FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
      result(FlutterError(code: "update", message: "Move Harbor to a writable Applications folder before updating.", details: nil)); return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let source = URL(fileURLWithPath: path)
      let parent = target.deletingLastPathComponent()
      let staged = parent.appendingPathComponent(".Harbor-update-\(UUID().uuidString).app")
      let backup = parent.appendingPathComponent(".Harbor-backup-\(UUID().uuidString).app")
      do {
        guard let candidate = Bundle(url: source),
          candidate.bundleIdentifier == Bundle.main.bundleIdentifier,
          let number = candidate.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
          Int(number) == build,
          build > (Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0) else {
          throw NSError(domain: "HarborUpdate", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The update has an invalid identity or version."])
        }
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", source.path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else {
          throw NSError(domain: "HarborUpdate", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The downloaded application failed verification."])
        }
        try FileManager.default.copyItem(at: source, to: staged)
        let script = source.deletingLastPathComponent().appendingPathComponent("install.sh")
        // All paths are positional arguments, never interpolated into shell code.
        // Stage on the destination volume and preserve the old app for rollback.
        let body = #"""
        #!/bin/sh
        owner="$1"; target="$2"; staged="$3"; backup="$4"; work="$5"
        count=0
        while /bin/kill -0 "$owner" 2>/dev/null; do
          count=$((count + 1))
          if [ "$count" -ge 60 ]; then
            /bin/rm -rf "$staged" "$work"
            exit 1
          fi
          /bin/sleep 1
        done
        if /bin/mv "$target" "$backup"; then
          if /bin/mv "$staged" "$target"; then
            if /usr/bin/open "$target"; then
              /bin/rm -rf "$backup" "$work"
              exit 0
            fi
            /bin/mv "$target" "$staged"
          fi
          /bin/mv "$backup" "$target"
        fi
        /usr/bin/open "$target"
        /bin/rm -rf "$staged" "$work"
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
          self.shutdownConnections {
            do {
              let installer = Process()
              installer.executableURL = URL(fileURLWithPath: "/bin/sh")
              installer.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                target.path, staged.path, backup.path, source.deletingLastPathComponent().path]
              installer.standardInput = FileHandle.nullDevice
              installer.standardOutput = FileHandle.nullDevice
              installer.standardError = FileHandle.nullDevice
              try installer.run()
              result(nil)
              NSApp.terminate(nil)
            } catch {
              try? FileManager.default.removeItem(at: staged)
              result(FlutterError(code: "update", message: error.localizedDescription, details: nil))
            }
          }
        }
      } catch {
        try? FileManager.default.removeItem(at: staged)
        DispatchQueue.main.async {
          result(FlutterError(code: "update", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  @objc private func performHarborCommand(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    commandChannel?.invokeMethod(command, arguments: nil)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.charactersIgnoringModifiers?.lowercased() == "f",
       modifiers == [.command] || modifiers == [.control] {
      commandChannel?.invokeMethod("search", arguments: nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
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
    installLaunchCover()
    let channel = FlutterMethodChannel(name: "harbor/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "systemProxy" {
        self.systemProxy(call.arguments, result: result)
        return
      }
      if call.method == "installUpdate" {
        self.installUpdate(call.arguments, result: result)
        return
      }
      if call.method == "firstFrameReady" {
        self.revealFlutter()
        result(nil)
        return
      }
      if call.method == "applicationInfo" {
        result([
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
          "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        ])
        return
      }
      guard call.method == "pickPrivateKey" || call.method == "pickIdentityFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let panel = NSOpenPanel()
      let selectingIdentity = call.method == "pickIdentityFile"
      panel.title = selectingIdentity ? "Select SSH identity file" : "Import SSH private key"
      panel.prompt = selectingIdentity ? "Select" : "Import"
      if selectingIdentity {
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".ssh", isDirectory: true)
      }
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
    self.delegate = self
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
