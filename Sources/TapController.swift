import Cocoa
import CoreGraphics

/// ⌘単押し検出の状態機械と CGEventTap の管理（keyremap-spec.md §6.2）
final class TapController {
    enum Side: String {
        case left, right

        var configSide: Config.TapSide {
            self == .left ? .leftCommand : .rightCommand
        }
    }

    private enum State {
        case idle
        case candidate(Side, CFTimeInterval)
        case aborted(Side)
    }

    // virtual keycode (kVK_)
    private static let leftCommandKeycode: Int64 = 0x37
    private static let rightCommandKeycode: Int64 = 0x36

    // device-dependent modifier mask (NX_)
    private static let deviceLeftCommandMask: UInt64 = 0x00000008
    private static let deviceRightCommandMask: UInt64 = 0x00000010

    /// 自分が post したイベントの再入判別マーカー ("KRMP")
    private static let selfEventMarker: Int64 = 0x4B52_4D50

    /// 単押し判定の閾値（設定ファイルの tap_threshold_ms）
    var tapThresholdMs: Double = 400

    /// 各サイドの単押しアクション（設定ファイルの tap_actions）
    var tapActions: [Config.TapSide: Config.TapAction] = [.leftCommand: .eisu, .rightCommand: .kana]

    var isRunning: Bool { eventTap != nil }

    private var state: State = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let postEventSource: CGEventSource?

    init() {
        postEventSource = CGEventSource(stateID: .hidSystemState)
        postEventSource?.userData = Self.selfEventMarker
    }

    // MARK: - Tap lifecycle

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: UInt64 =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<TapController>.fromOpaque(userInfo).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.write("tap: create failed (accessibility not granted?)")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("tap: started")
        return true
    }

    /// 一時停止/再開（FR-5.4）。停止中はイベントが素通しになる
    func setEnabled(_ enabled: Bool) {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        state = .idle
        Log.write("tap: \(enabled ? "enabled" : "disabled") by user")
    }

    /// スリープ復帰等で tap が死んでいないか検証し、必要なら復旧する
    func ensureEnabled() {
        guard let tap = eventTap else {
            _ = start()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.write("tap: re-enabled (was disabled)")
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // コールバック遅延等で OS に切られたら即再有効化する（最重要のエラーハンドリング）
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.write("tap: disabled by OS (\(type.rawValue)), re-enabled")
            return nil

        case .flagsChanged:
            handleFlagsChanged(event)

        default:
            // keyDown / keyUp / マウス / スクロール → 修飾キー用途とみなしてアボート
            // ただし自分が post したイベントでは状態を変えない
            if event.getIntegerValueField(.eventSourceUserData) != Self.selfEventMarker,
               case .candidate(let side, _) = state {
                state = .aborted(side)
                Log.write("state: aborted(\(side.rawValue)) by event type \(type.rawValue)")
            }
        }
        // FR-2.4: イベントは consume も改変もせず必ず下流へ流す
        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let rawFlags = event.flags.rawValue

        guard keycode == Self.leftCommandKeycode || keycode == Self.rightCommandKeycode else {
            // 別の修飾キー（Shift / Ctrl / Opt / CapsLock / fn）→ アボート
            if case .candidate(let side, _) = state {
                state = .aborted(side)
                Log.write("state: aborted(\(side.rawValue)) by other modifier keycode \(keycode)")
            }
            return
        }

        let side: Side = keycode == Self.leftCommandKeycode ? .left : .right
        let deviceMask = side == .left ? Self.deviceLeftCommandMask : Self.deviceRightCommandMask
        let isDown = (rawFlags & deviceMask) != 0

        if isDown {
            switch state {
            case .idle:
                state = .candidate(side, CACurrentMediaTime())
            case .candidate(let current, _) where current != side:
                // 左右同時押し → アボート
                state = .aborted(current)
                Log.write("state: aborted(\(current.rawValue)) by opposite command down")
            default:
                break
            }
        } else {
            switch state {
            case .candidate(let current, let downTime) where current == side:
                let elapsedMs = (CACurrentMediaTime() - downTime) * 1000
                if elapsedMs <= tapThresholdMs {
                    fire(side)
                } else {
                    Log.write("state: hold timeout \(Int(elapsedMs))ms (\(side.rawValue)), no fire")
                }
                state = .idle
            case .aborted(let current) where current == side:
                state = .idle
            default:
                break
            }
        }
    }

    // MARK: - Key posting

    private func fire(_ side: Side) {
        guard let action = tapActions[side.configSide] else {
            Log.write("fire: \(side.rawValue) has no action, skipped")
            return
        }
        Log.write("fire: \(side.rawValue) -> \(action.rawValue)")
        // ⌘ up イベントが下流に届いてから post されるよう、callback の外で実行する
        let key = action.keyCode
        DispatchQueue.main.async { [weak self] in
            self?.postKey(key)
        }
    }

    private func postKey(_ key: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: postEventSource, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: postEventSource, virtualKey: key, keyDown: false)
        down?.flags = [] // ⌘フラグの残留を明示的にクリア
        up?.flags = []
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
