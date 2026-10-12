import CryptoKit
import Foundation

/// 内容哈希，用于判断“同一条内容被复制了两次”。
enum ContentHash {
    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}
