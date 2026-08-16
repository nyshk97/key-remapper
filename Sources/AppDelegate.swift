import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tapController = TapController()
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.write("launch: pid \(ProcessInfo.processInfo.processIdentifier)")

        // Layer 1 の適用（FR-3.2: 起動時 / スリープ復帰時）
        HidutilApplier.apply()

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
                }
            }
        }

        // スリープ復帰・ロック解除で tap の有効性を検証する
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.write("wake: verifying tap and reapplying hidutil")
            self?.tapController.ensureEnabled()
            HidutilApplier.apply()
        }
    }

    private func startTap() {
        if !tapController.start() {
            Log.write("tap: start failed, will retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startTap()
            }
        }
    }
}
