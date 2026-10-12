import Foundation
import os

/// 统一日志，可用 Console.app 或 log stream 观察。
enum Log {
    nonisolated private static let subsystem = "com.river.Clip"

    // Logger 是 Sendable，声明为 nonisolated 才能从任意 actor 上直接使用。
    nonisolated static let monitor = Logger(subsystem: subsystem, category: "monitor")
    nonisolated static let store = Logger(subsystem: subsystem, category: "store")
    nonisolated static let panel = Logger(subsystem: subsystem, category: "panel")
    nonisolated static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
