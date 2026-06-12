import Cocoa
import FlutterMacOS
import Security
import ServiceManagement

private func debugLog(_ message: @autoclosure () -> String) {
  #if DEBUG
  print(message())
  #endif
}

// MARK: - KeychainCredentials

/// Keychain-backed credential storage with one-time migration from the legacy
/// ~/Library/Application Support/com.beamvo/credentials.json plaintext store.
class KeychainCredentials {
  static let shared = KeychainCredentials()

  private let service = "com.beamvo.Beeamvo.credentials"
  private let directory = "com.beamvo"
  private let filename = "credentials.json"

  private init() {}

  private var fileURL: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent(directory)
    return dir.appendingPathComponent(filename)
  }

  private func loadLegacyStore() -> [String: String] {
    guard let data = try? Data(contentsOf: fileURL),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
      return [:]
    }
    return dict
  }

  private func saveLegacyStore(_ store: [String: String]) -> Bool {
    do {
      if store.isEmpty {
        if FileManager.default.fileExists(atPath: fileURL.path) {
          try FileManager.default.removeItem(at: fileURL)
        }
      } else {
        guard let data = try? JSONSerialization.data(withJSONObject: store) else { return false }
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
      }
      return true
    } catch {
      debugLog("[KeychainCredentials] Legacy store update failed: \(error)")
      return false
    }
  }

  private func removeLegacyValue(account: String) {
    var store = loadLegacyStore()
    guard store.removeValue(forKey: account) != nil else { return }
    if saveLegacyStore(store) {
      debugLog("[KeychainCredentials] Removed legacy plaintext value")
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }

  private func statusMessage(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) {
      return message as String
    }
    return "OSStatus \(status)"
  }

  func read(account: String) -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecSuccess {
      guard let data = item as? Data,
            let value = String(data: data, encoding: .utf8) else {
        debugLog("[KeychainCredentials] ERROR: Could not decode Keychain value")
        return nil
      }
      return value
    }

    guard status == errSecItemNotFound else {
      debugLog("[KeychainCredentials] Read failed: \(statusMessage(status))")
      return nil
    }

    let legacyStore = loadLegacyStore()
    guard let legacyValue = legacyStore[account] else {
      return nil
    }

    if write(account: account, value: legacyValue) {
      debugLog("[KeychainCredentials] Migrated legacy value to Keychain")
      return legacyValue
    }

    debugLog("[KeychainCredentials] ERROR: Legacy migration failed")
    return nil
  }

  func write(account: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else {
      debugLog("[KeychainCredentials] ERROR: Could not encode credential")
      return false
    }

    var addQuery = baseQuery(account: account)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      removeLegacyValue(account: account)
      return true
    }

    guard addStatus == errSecDuplicateItem else {
      debugLog("[KeychainCredentials] Write failed: \(statusMessage(addStatus))")
      return false
    }

    let updateStatus = SecItemUpdate(
      baseQuery(account: account) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )

    if updateStatus == errSecSuccess {
      removeLegacyValue(account: account)
      return true
    }

    debugLog("[KeychainCredentials] Update failed: \(statusMessage(updateStatus))")
    return false
  }

  func delete(account: String) -> Bool {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    removeLegacyValue(account: account)

    if status == errSecSuccess || status == errSecItemNotFound {
      return true
    }

    debugLog("[KeychainCredentials] Delete failed: \(statusMessage(status))")
    return false
  }
}

// MARK: - MainFlutterWindow

class MainFlutterWindow: NSWindow {
  private var methodChannel: FlutterMethodChannel?
  private var credentialsChannel: FlutterMethodChannel?
  private var launchAtLoginChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // CRITICAL: Set FlutterViewController background to clear for transparency
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register whisper.cpp offline transcription plugin
    let whisperRegistrar = flutterViewController.registrar(forPlugin: "WhisperPlugin")
    WhisperPlugin.register(with: whisperRegistrar)

    // Register credentials channel
    registerCredentialsChannel(flutterViewController: flutterViewController)

    // Register launch-at-login channel
    registerLaunchAtLoginChannel(flutterViewController: flutterViewController)

    // Make window transparent
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.hasShadow = false
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    // Hide the standard window buttons
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true

    // Make Flutter view transparent
    let flutterView = flutterViewController.view
    flutterView.wantsLayer = true
    flutterView.layer?.isOpaque = false
    flutterView.layer?.backgroundColor = CGColor.clear

    // Make content view transparent
    if let contentView = self.contentView {
      contentView.wantsLayer = true
      contentView.layer?.isOpaque = false
      contentView.layer?.backgroundColor = CGColor.clear
    }

    // Window level: statusBar is above fullscreen menu bar
    self.level = .statusBar

    // Collection behavior for multi-Space and fullscreen support
    self.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle
    ]

    self.ignoresMouseEvents = false
    self.isExcludedFromWindowsMenu = true

    // Set up method channel for native window control
    methodChannel = FlutterMethodChannel(
      name: "beeamvo/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window not available", details: nil))
        return
      }
      
      switch call.method {
      case "hide":
        // Use alpha transparency for hiding - works better than orderOut or positioning
        self.alphaValue = 0
        // CRITICAL: Ignore mouse events when hidden to prevent blocking clicks
        self.ignoresMouseEvents = true
        result(nil)
        
      case "show":
        self.alphaValue = 1
        self.level = .statusBar
        // Re-enable mouse events when showing
        self.ignoresMouseEvents = false
        self.orderFront(nil)
        result(nil)
        
      case "showWithoutFocus":
        self.alphaValue = 1
        self.level = .statusBar
        // Re-enable mouse events when showing
        self.ignoresMouseEvents = false
        self.orderFrontRegardless()
        result(nil)
        
      case "positionAtBottomCenter":
        if let args = call.arguments as? [String: Double],
           let width = args["width"],
           let height = args["height"] {
          self.positionAtBottomCenter(width: width, height: height)
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Expected width and height", details: nil))
        }
        
      case "setPosition":
        if let args = call.arguments as? [String: Double],
           let x = args["x"],
           let y = args["y"] {
          self.setFrameOrigin(NSPoint(x: x, y: y))
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Expected x and y", details: nil))
        }
        
      case "isVisible":
        result(self.alphaValue > 0)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func registerCredentialsChannel(flutterViewController: FlutterViewController) {
    debugLog("[MainFlutterWindow] Registering credentials channel...")

    credentialsChannel = FlutterMethodChannel(
      name: "com.beamvo/keychain_credentials",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    credentialsChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      debugLog("[CredentialsChannel] Received method call: \(call.method)")

      guard self != nil else {
        debugLog("[CredentialsChannel] ERROR: Window not available")
        result(FlutterError(code: "UNAVAILABLE", message: "Window not available", details: nil))
        return
      }

      switch call.method {
      case "read":
        guard let args = call.arguments as? [String: Any],
              let account = args["account"] as? String else {
          debugLog("[CredentialsChannel] ERROR: Missing account parameter")
          result(FlutterError(code: "INVALID_ARGS", message: "Missing account parameter", details: nil))
          return
        }
        let value = KeychainCredentials.shared.read(account: account)
        result(value)

      case "write":
        guard let args = call.arguments as? [String: Any],
              let account = args["account"] as? String,
              let value = args["value"] as? String else {
          debugLog("[CredentialsChannel] ERROR: Missing account or value parameter")
          result(FlutterError(code: "INVALID_ARGS", message: "Missing account or value parameter", details: nil))
          return
        }
        let success = KeychainCredentials.shared.write(account: account, value: value)
        result(success)

      case "delete":
        guard let args = call.arguments as? [String: Any],
              let account = args["account"] as? String else {
          debugLog("[CredentialsChannel] ERROR: Missing account parameter")
          result(FlutterError(code: "INVALID_ARGS", message: "Missing account parameter", details: nil))
          return
        }
        debugLog("[CredentialsChannel] Deleting credential")
        let success = KeychainCredentials.shared.delete(account: account)
        debugLog("[CredentialsChannel] Delete result: \(success)")
        result(success)

      default:
        debugLog("[CredentialsChannel] ERROR: Unknown method: \(call.method)")
        result(FlutterMethodNotImplemented)
      }
    }

    debugLog("[MainFlutterWindow] ✓ Registered credentials channel")
  }

  private func registerLaunchAtLoginChannel(flutterViewController: FlutterViewController) {
    debugLog("[MainFlutterWindow] Registering launch-at-login channel...")

    launchAtLoginChannel = FlutterMethodChannel(
      name: "beeamvo/launch_at_login",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    launchAtLoginChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window not available", details: nil))
        return
      }

      switch call.method {
      case "isEnabled":
        let enabled = self.isLaunchAtLoginEnabled()
        debugLog("[LaunchAtLogin] isEnabled: \(enabled)")
        result(enabled)

      case "enable":
        debugLog("[LaunchAtLogin] Enabling launch at login...")
        let success = self.setLaunchAtLoginEnabled(true)
        result(success)

      case "disable":
        debugLog("[LaunchAtLogin] Disabling launch at login...")
        let success = self.setLaunchAtLoginEnabled(false)
        result(success)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    debugLog("[MainFlutterWindow] ✓ Registered launch-at-login channel")
  }

  // MARK: - Launch at Login Helpers

  private func getBundleID() -> String {
    return Bundle.main.bundleIdentifier ?? "com.beamvo.Beeamvo"
  }

  private func getAppURL() -> URL? {
    return Bundle.main.bundleURL
  }

  func isLaunchAtLoginEnabled() -> Bool {
    guard let appURL = getAppURL() else {
      debugLog("[LaunchAtLogin] ERROR: Could not get app URL")
      return false
    }

    debugLog("[LaunchAtLogin] Checking login item")

    // Use LSSharedFileList to check if app is in login items
    guard let loginItemsUnmanaged = LSSharedFileListCreate(
      nil,
      kLSSharedFileListSessionLoginItems.takeRetainedValue() as CFString,
      nil
    ) else {
      debugLog("[LaunchAtLogin] ERROR: Could not create login items list")
      return false
    }
    let loginItems = loginItemsUnmanaged.takeRetainedValue()

    guard let itemSnapshotUnmanaged = LSSharedFileListCopySnapshot(loginItems, nil) else {
      debugLog("[LaunchAtLogin] ERROR: Could not copy snapshot")
      return false
    }
    let itemSnapshot = itemSnapshotUnmanaged.takeRetainedValue() as NSArray

    for case let item as LSSharedFileListItem in itemSnapshot {
      guard let itemURLUnmanaged = LSSharedFileListItemCopyResolvedURL(item, 0, nil) else { continue }
      let itemURL = itemURLUnmanaged.takeRetainedValue() as URL

      if itemURL.path == appURL.path {
        debugLog("[LaunchAtLogin] Found matching login item")
        return true
      }
    }

    debugLog("[LaunchAtLogin] No matching login item found")
    return false
  }

  func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
    guard let appURL = getAppURL() else {
      debugLog("[LaunchAtLogin] ERROR: Could not get app URL")
      return false
    }

    let bundleID = getBundleID()
    debugLog("[LaunchAtLogin] Setting launch at login to \(enabled)")

    guard let loginItemsUnmanaged = LSSharedFileListCreate(
      nil,
      kLSSharedFileListSessionLoginItems.takeRetainedValue() as CFString,
      nil
    ) else {
      debugLog("[LaunchAtLogin] ERROR: Could not create login items list")
      return false
    }
    let loginItems = loginItemsUnmanaged.takeRetainedValue()

    // First, remove any existing entry for this app
    if let itemSnapshotUnmanaged = LSSharedFileListCopySnapshot(loginItems, nil) {
      let itemSnapshot = itemSnapshotUnmanaged.takeRetainedValue() as NSArray
      for case let item as LSSharedFileListItem in itemSnapshot {
        if let itemURLUnmanaged = LSSharedFileListItemCopyResolvedURL(item, 0, nil) {
          let itemURL = itemURLUnmanaged.takeRetainedValue() as URL
          if itemURL.path == appURL.path {
            LSSharedFileListItemRemove(loginItems, item)
            debugLog("[LaunchAtLogin] Removed existing login item")
            break
          }
        }
      }
    }

    // Add new entry if enabled
    if enabled {
      let item = LSSharedFileListInsertItemURL(
        loginItems,
        kLSSharedFileListItemLast.takeRetainedValue(),
        bundleID as CFString,
        nil,
        appURL as CFURL,
        nil,
        nil
      )

      if item != nil {
        debugLog("[LaunchAtLogin] ✓ Successfully added login item")
        return true
      } else {
        debugLog("[LaunchAtLogin] ✗ Failed to add login item")
        return false
      }
    } else {
      debugLog("[LaunchAtLogin] ✓ Successfully removed login item")
      return true
    }
  }

  private func positionAtBottomCenter(width: Double, height: Double) {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let screenFrame = screen?.visibleFrame else { return }
    
    let x = screenFrame.origin.x + (screenFrame.width / 2) - (width / 2)
    let y = screenFrame.origin.y + 60  // 60px from bottom
    
    self.setContentSize(NSSize(width: width, height: height))
    self.setFrameOrigin(NSPoint(x: x, y: y))
    
    // Show window
    self.alphaValue = 1
    self.level = .statusBar
    self.orderFrontRegardless()
  }
  
  override var canBecomeKey: Bool {
    return true
  }
  
  override var canBecomeMain: Bool {
    return true
  }
}
