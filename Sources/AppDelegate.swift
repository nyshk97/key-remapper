import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tapController = TapController()
    private var menuBarController: MenuBarController?
    private var permissionPollTimer: Timer?

    private(set) var config: Config = .fallback
    private(set) var configErrorDescription: String?
    private(set) var isPaused = false

    var isTapHealthy: Bool { tapController.isRunning }

    var statusDescription: String {
        var parts: [String] = []
        if !AXIsProcessTrusted() {
            parts.append("アクセシビリティ権限待ち")
        } else if isPaused {
            parts.append("一時停止中")
        } else if !tapController.isRunning {
            parts.append("起動処理中…")
        } else {
            parts.append("稼働中")
        }
        if configErrorDescription != nil {
            parts.append("設定エラー（ログ参照）")
        }
        if IsSecureEventInputEnabled() {
            parts.append("Secure Input 中")
        }
        return parts.joined(separator: " / ")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateIfAlreadyRunning()
        Log.write("launch: pid \(ProcessInfo.processInfo.processIdentifier)")

        // 設定の読み込みと Layer 1 の適用（FR-3.2: 起動時）
        reloadConfig(showAlertOnError: false)

        menuBarController = MenuBarController(app: self)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTap()
        } else {
            Log.write("accessibility: not granted, polling until granted")
            permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionPollTimer = nil
                    Log.write("accessibility: granted")
                    self?.startTap()
                    self?.menuBarController?.refresh()
                }
            }
        }

        // スリープ復帰・ロック解除で tap と Layer 1 の有効性を検証する
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            Log.write("wake: verifying tap and reapplying hidutil")
            self.tapController.ensureEnabled()
            if self.configErrorDescription == nil {
                HidutilApplier.applySafely(self.config)
            }
        }

        #if !DEBUG
        // 本番ビルドは初回起動時にログイン項目へ自動登録する（FR-3.1）
        // 未登録時の status は .notRegistered でなく .notFound が返ることがある
        switch SMAppService.mainApp.status {
        case .enabled:
            break
        case .requiresApproval:
            Log.write("login item: requires approval in System Settings")
        default:
            do {
                try SMAppService.mainApp.register()
                Log.write("login item: auto-registered")
            } catch {
                Log.write("login item: auto-register failed: \(error)")
            }
        }
        #endif
    }

    // MARK: - Config

    func reloadConfig(showAlertOnError: Bool) {
        switch Config.load() {
        case .success(let loaded):
            config = loaded
            configErrorDescription = nil
            tapController.tapThresholdMs = loaded.tapThresholdMs
            tapController.tapActions = loaded.tapActions
            if !isPaused {
                HidutilApplier.applySafely(loaded)
            }
            Log.write("config: loaded (remaps: \(loaded.remaps.count), threshold: \(Int(loaded.tapThresholdMs))ms)")
        case .failure(let error):
            // 失敗時は直前の設定と hidutil の現状を維持する
            configErrorDescription = "\(error)"
            Log.write("config: load failed: \(error)")
            if showAlertOnError {
                let alert = NSAlert()
                alert.messageText = "設定の読み込みに失敗しました"
                alert.informativeText = "\(error)\n\n直前の設定で動作を継続します。"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    // MARK: - Pause (FR-5.4: 両層を無効化)

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            tapController.setEnabled(false)
            HidutilApplier.clearForPause()
            Log.write("paused")
        } else {
            tapController.setEnabled(true)
            if configErrorDescription == nil {
                HidutilApplier.applySafely(config)
            }
            Log.write("resumed")
        }
    }

    // MARK: - Helpers

    private func startTap() {
        if !tapController.start() {
            Log.write("tap: start failed, will retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startTap()
            }
        }
        menuBarController?.refresh()
    }

    private func terminateIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            Log.write("launch: another instance is running (pid \(others.map { $0.processIdentifier })), exiting")
            NSApp.terminate(nil)
        }
    }
}
