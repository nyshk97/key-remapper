import CoreGraphics
import Foundation

/// 設定ファイル（keyremap-spec.md §6.3）の読み込みとバリデーション
struct Config {
    struct Remap {
        let from: String
        let to: String
    }

    enum TapSide: String {
        case leftCommand = "left_command"
        case rightCommand = "right_command"
    }

    enum TapAction: String {
        case eisu
        case kana

        var keyCode: CGKeyCode {
            switch self {
            case .eisu: return 0x66
            case .kana: return 0x68
            }
        }
    }

    var remaps: [Remap]
    var tapActions: [TapSide: TapAction]
    var tapThresholdMs: Double

    static let path = NSHomeDirectory() + "/.config/keyrc/config.json"

    /// 設定が読めないときのフォールバック。
    /// remaps が空 = 「hidutil には触らない」を意味する（適用すると既存マッピングを消してしまうため、
    /// 読み込み失敗時は hidutil を適用しないこと）
    static let fallback = Config(
        remaps: [],
        tapActions: [.leftCommand: .eisu, .rightCommand: .kana],
        tapThresholdMs: 400
    )

    /// キー名は Karabiner の命名に寄せる
    static let keyUsages: [String: UInt64] = [
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

    enum LoadError: Error, CustomStringConvertible {
        case notFound(String)
        case decodeFailed(String)
        case unknownKeyName(String)
        case unknownTapEntry(String)

        var description: String {
            switch self {
            case .notFound(let path): return "設定ファイルが見つかりません: \(path)"
            case .decodeFailed(let detail): return "設定ファイルの JSON が不正です: \(detail)"
            case .unknownKeyName(let name): return "remaps に不明なキー名があります: \(name)"
            case .unknownTapEntry(let detail): return "tap_actions に不明な値があります: \(detail)"
            }
        }
    }

    static func load() -> Result<Config, LoadError> {
        guard let data = FileManager.default.contents(atPath: path) else {
            return .failure(.notFound(path))
        }

        let raw: RawConfig
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            raw = try decoder.decode(RawConfig.self, from: data)
        } catch {
            return .failure(.decodeFailed("\(error)"))
        }

        let remaps = (raw.remaps ?? []).map { Remap(from: $0.from, to: $0.to) }
        for remap in remaps {
            for name in [remap.from, remap.to] where keyUsages[name] == nil {
                return .failure(.unknownKeyName(name))
            }
        }

        var tapActions: [TapSide: TapAction] = [:]
        for entry in raw.tapActions ?? [] {
            guard let side = TapSide(rawValue: entry.key), let action = TapAction(rawValue: entry.action) else {
                return .failure(.unknownTapEntry("\(entry.key) -> \(entry.action)"))
            }
            tapActions[side] = action
        }

        return .success(Config(
            remaps: remaps,
            tapActions: tapActions,
            tapThresholdMs: raw.tapThresholdMs ?? 400
        ))
    }
}

private struct RawConfig: Decodable {
    struct RawRemap: Decodable {
        let from: String
        let to: String
    }

    struct RawTapAction: Decodable {
        let key: String
        let action: String
    }

    let remaps: [RawRemap]?
    let tapActions: [RawTapAction]?
    let tapThresholdMs: Double?
}
