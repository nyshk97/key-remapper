import AppKit
import ServiceManagement

/// メニューバー常駐 UI（FR-5.3: 状態表示 / 一時停止 / 設定を開く / 再読み込み）
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "一時停止", action: #selector(togglePause(_:)), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")

    init(app: AppDelegate) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(NSMenuItem.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)

        let reloadItem = NSMenuItem(title: "設定を再読み込み", action: #selector(reloadConfig(_:)), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openItem = NSMenuItem(title: "設定ファイルを開く", action: #selector(openConfig(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        #if DEBUG
        let versionTitle = "keyrc v\(version) (dev)"
        #else
        let versionTitle = "keyrc v\(version)"
        #endif
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        #if !DEBUG
        let updateItem = NSMenuItem(title: "アップデートを確認…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        #endif

        let quitItem = NSMenuItem(title: "終了", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.autoenablesItems = false
        statusItem.menu = menu
        refresh()
        Log.write("menu: status item installed")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        statusLine.title = app.statusDescription
        pauseItem.title = app.isPaused ? "再開" : "一時停止"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let symbolName = (app.isPaused || !app.isTapHealthy) ? "keyboard.slash" : "keyboard"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "keyrc")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Actions

    @objc private func togglePause(_ sender: Any?) {
        app.setPaused(!app.isPaused)
        refresh()
    }

    @objc private func reloadConfig(_ sender: Any?) {
        app.reloadConfig(showAlertOnError: true)
        refresh()
    }

    @objc private func openConfig(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: Config.path))
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Log.write("login item: unregistered")
            } else {
                try SMAppService.mainApp.register()
                Log.write("login item: registered")
            }
        } catch {
            Log.write("login item: operation failed: \(error)")
        }
        refresh()
    }

    #if !DEBUG
    @objc private func checkForUpdates(_ sender: Any?) {
        app.checkForUpdates()
    }
    #endif

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
