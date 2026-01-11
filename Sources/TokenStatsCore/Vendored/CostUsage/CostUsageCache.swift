import Foundation

enum CostUsageCacheIO {
    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(provider: UsageProvider, cacheRoot: URL? = nil, allTime: Bool = false) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        let suffix = allTime ? "-alltime" : ""
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-v1\(suffix).json", isDirectory: false)
    }

    static func load(provider: UsageProvider, cacheRoot: URL? = nil, allTime: Bool = false) -> CostUsageCache {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot, allTime: allTime)
        if let decoded = self.loadCache(at: url) { return decoded }
        return CostUsageCache()
    }

    private static func loadCache(at url: URL) -> CostUsageCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data)
        else { return nil }
        guard decoded.version == 1 else { return nil }
        return decoded
    }

    static func save(provider: UsageProvider, cache: CostUsageCache, cacheRoot: URL? = nil, allTime: Bool = false) {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot, allTime: allTime)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(cache)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct CostUsageCache: Codable, Sendable {
    var version: Int = 1
    var lastScanUnixMs: Int64 = 0

    // filePath -> file usage
    var files: [String: CostUsageFileUsage] = [:]

    // dayKey -> model -> packed usage
    var days: [String: [String: [Int]]] = [:]

    // rootPath -> mtime (for Claude roots)
    var roots: [String: Int64]?
}

struct CostUsageFileUsage: Codable, Sendable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
    var parsedBytes: Int64?
    var lastModel: String?
    var lastTotals: CostUsageCodexTotals?
}

struct CostUsageCodexTotals: Codable, Sendable {
    var input: Int
    var cached: Int
    var output: Int
}
