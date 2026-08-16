import Foundation

/// 設定の remaps を hidutil UserKeyMapping に変換して適用する（Layer 1）
///
/// 注意: 「クリア → 即時再適用」はプロパティ上は載っていても実効しない状態を
/// 引き起こすことがある（M2 で実測）。通常の適用は既存値の上書きのみ行い、
/// クリア（一時停止）後の再適用は安全マージンを空けてから行う。
enum HidutilApplier {
    private static let usagePageKeyboard: UInt64 = 0x700000000
    private static let safeIntervalAfterClear: TimeInterval = 3.0
    private static var lastClearAt: Date?

    /// 設定を適用する。直近にクリアしていた場合は安全マージン分だけ遅延させる
    static func applySafely(_ config: Config) {
        guard !config.remaps.isEmpty else {
            Log.write("hidutil: remaps is empty, skipping apply")
            return
        }
        var mapping: [[String: UInt64]] = []
        for remap in config.remaps {
            guard let src = Config.keyUsages[remap.from], let dst = Config.keyUsages[remap.to] else {
                // load() でバリデーション済みのため通常は到達しない
                Log.write("hidutil: unknown key name \(remap.from)/\(remap.to), skipping apply")
                return
            }
            mapping.append([
                "HIDKeyboardModifierMappingSrc": usagePageKeyboard + src,
                "HIDKeyboardModifierMappingDst": usagePageKeyboard + dst,
            ])
        }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mapping]),
              let payload = String(data: payloadData, encoding: String.Encoding.utf8) else {
            Log.write("hidutil: payload serialization failed")
            return
        }

        let elapsed = lastClearAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0, safeIntervalAfterClear - elapsed)
        if delay > 0 {
            Log.write("hidutil: delaying apply \(String(format: "%.1f", delay))s (recent clear)")
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            run(payload: payload, label: "applied \(mapping.count) mappings")
        }
    }

    /// 一時停止用: マッピングを空にする
    static func clearForPause() {
        lastClearAt = Date()
        DispatchQueue.global(qos: .utility).async {
            run(payload: "{\"UserKeyMapping\":[]}", label: "cleared (paused)")
        }
    }

    private static func run(payload: String, label: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", payload]
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            Log.write("hidutil: \(label) (exit \(process.terminationStatus))")
        } catch {
            Log.write("hidutil: failed to run: \(error)")
        }
    }
}
