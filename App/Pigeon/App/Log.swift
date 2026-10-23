import os

/// The app's loggers, a category per area.
nonisolated enum Log {
    private static let subsystem = "com.pbordjadze.pigeon"

    static let drive = Logger(subsystem: subsystem, category: "drive")
    #if DEBUG
    static let demo = Logger(subsystem: subsystem, category: "demo")
    #endif
}
