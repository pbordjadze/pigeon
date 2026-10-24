import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.pigeon"

    static let drive = Logger(subsystem: subsystem, category: "drive")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let maps = Logger(subsystem: subsystem, category: "maps")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: "demo")
    #endif
}
