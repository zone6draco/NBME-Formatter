import Foundation

struct AppPaths {
    static let appSupport: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let dir = base.appendingPathComponent("NMBEcombine", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }()

    static var downloads: URL {
        appSupport.appendingPathComponent("downloads", isDirectory: true)
    }

    static var processed: URL {
        appSupport.appendingPathComponent("processed", isDirectory: true)
    }
}
