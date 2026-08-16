import Foundation

/// 設定ファイルの remaps を hidutil UserKeyMapping に変換して適用する（Layer 1）
///
/// 注意: 「クリア → 即時再適用」はプロパティ上は載っていても実効しない状態を
/// 引き起こすことがある（M2 で実測）。ここでは既存値の上書きのみ行い、クリアは挟まない。
enum HidutilApplier {
    private static let usagePageKeyboard: UInt64 = 0x700000000

    /// キー名は Karabiner の命名に寄せる（keyremap-spec.md §6.3）
    private static let keyUsages: [String: UInt64] = [
        "return_or_enter": 0x28,
        "escape": 0x29,
        "delete_or_backspace": 0x2A,
        "tab": 0x2B,
        "spacebar": 0x2C,
        "hyphen": 0x2D,
        "equal_sign": 0x2E,
        "open_bracket": 0x2F,
        "close_bracket": 0x30,
        "backslash": 0x31,
        "semicolon": 0x33,
        "quote": 0x34,
        "grave_accent_and_tilde": 0x35,
        "comma": 0x36,
        "period": 0x37,
        "slash": 0x38,
        "caps_lock": 0x39,
        "left_control": 0xE0,
        "left_shift": 0xE1,
        "left_option": 0xE2,
        "left_command": 0xE3,
        "right_control": 0xE4,
        "right_shift": 0xE5,
        "right_option": 0xE6,
        "right_command": 0xE7,
    ]

    private struct Remap: Decodable {
        let from: String
        let to: String
    }

    private struct Config: Decodable {
        let remaps: [Remap]
    }

    static func apply() {
        let configPath = NSHomeDirectory() + "/.config/key-remapper/config.json"
        guard let data = FileManager.default.contents(atPath: configPath) else {
            Log.write("hidutil: config not found at \(configPath)")
            return
        }
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.write("hidutil: config parse failed: \(error)")
            return
        }

        var mapping: [[String: UInt64]] = []
        for remap in config.remaps {
            guard let src = keyUsages[remap.from], let dst = keyUsages[remap.to] else {
                Log.write("hidutil: unknown key name \(remap.from) -> \(remap.to), skipping all")
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

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            process.arguments = ["property", "--set", payload]
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                Log.write("hidutil: applied \(mapping.count) mappings (exit \(process.terminationStatus))")
            } catch {
                Log.write("hidutil: failed to run: \(error)")
            }
        }
    }
}
