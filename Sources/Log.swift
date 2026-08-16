import Foundation

/// open 経由の起動では stdout を捕捉できないため、ファイルに追記する
enum Log {
    #if DEBUG
    static let path = "/tmp/key-remapper-dev.log"
    #else
    static let path = "/tmp/key-remapper.log"
    #endif

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(line.data(using: String.Encoding.utf8)!)
        handle.closeFile()
    }
}
