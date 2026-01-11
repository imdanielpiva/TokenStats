import Foundation

extension CostUsageScanner {
    // MARK: - Amp

    /// Default Amp threads root directory.
    static func defaultAmpRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/amp/threads", isDirectory: true)
    }

    /// Parses an Amp thread JSON file and extracts usage by day.
    /// Returns a dictionary of dayKey -> model -> [inputTokens, cacheRead, cacheCreate, outputTokens, costNanos].
    static func parseAmpFile(
        fileURL: URL,
        range: CostUsageDayRange) -> AmpParseResult
    {
        var days: [String: [String: [Int]]] = [:]
        let costScale = 1_000_000_000.0

        struct AmpTokens: Sendable {
            let input: Int
            let cacheRead: Int
            let cacheCreate: Int
            let output: Int
            let costNanos: Int
        }

        func add(dayKey: String, model: String, tokens: AmpTokens) {
            guard CostUsageDayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey)
            else { return }
            let normModel = Self.normalizeAmpModel(model)
            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0, 0, 0]
            packed[0] = (packed[safe: 0] ?? 0) + tokens.input
            packed[1] = (packed[safe: 1] ?? 0) + tokens.cacheRead
            packed[2] = (packed[safe: 2] ?? 0) + tokens.cacheCreate
            packed[3] = (packed[safe: 3] ?? 0) + tokens.output
            packed[4] = (packed[safe: 4] ?? 0) + tokens.costNanos
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        guard let data = try? Data(contentsOf: fileURL),
              let thread = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return AmpParseResult(days: [:])
        }

        // Thread created timestamp (epoch ms) → day key
        let threadCreatedMs = thread["created"] as? Double ?? 0
        let threadDayKey = Self.dayKeyFromEpochMs(threadCreatedMs)

        guard let messages = thread["messages"] as? [[String: Any]] else {
            return AmpParseResult(days: [:])
        }

        for message in messages {
            guard let role = message["role"] as? String, role == "assistant" else { continue }
            guard let usage = message["usage"] as? [String: Any] else { continue }
            guard let model = usage["model"] as? String else { continue }

            let input = (usage["inputTokens"] as? NSNumber)?.intValue ?? 0
            let output = (usage["outputTokens"] as? NSNumber)?.intValue ?? 0
            let cacheRead = (usage["cacheReadInputTokens"] as? NSNumber)?.intValue ?? 0
            let cacheCreate = (usage["cacheCreationInputTokens"] as? NSNumber)?.intValue ?? 0
            let credits = (usage["credits"] as? NSNumber)?.doubleValue ?? 0

            if input == 0, output == 0, cacheRead == 0, cacheCreate == 0, credits == 0 { continue }

            // Amp stores cost in cents (pay-as-you-go, no markup) - convert to USD
            let costUSD = credits / 100.0
            let costNanos = Int((costUSD * costScale).rounded())

            // Use message timestamp if available, otherwise thread created timestamp
            let messageMeta = message["meta"] as? [String: Any]
            let sentAtMs = messageMeta?["sentAt"] as? Double
            let dayKey: String
            if let sentAtMs, sentAtMs > 0, let key = Self.dayKeyFromEpochMs(sentAtMs) {
                dayKey = key
            } else if let threadDayKey {
                dayKey = threadDayKey
            } else {
                continue
            }

            let tokens = AmpTokens(
                input: input,
                cacheRead: cacheRead,
                cacheCreate: cacheCreate,
                output: output,
                costNanos: costNanos)
            add(dayKey: dayKey, model: model, tokens: tokens)
        }

        return AmpParseResult(days: days)
    }

    /// Converts epoch milliseconds to a day key (YYYY-MM-DD).
    private static func dayKeyFromEpochMs(_ ms: Double) -> String? {
        guard ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Normalizes Amp model names (removes date suffix like -20251101).
    static func normalizeAmpModel(_ model: String) -> String {
        // claude-opus-4-5-20251101 → claude-opus-4-5
        // claude-sonnet-4-20250514 → claude-sonnet-4
        let pattern = #"-\d{8}$"#
        if let range = model.range(of: pattern, options: .regularExpression) {
            return String(model[..<range.lowerBound])
        }
        return model
    }

    struct AmpParseResult: Sendable {
        let days: [String: [String: [Int]]]
    }

    /// Main entry point for loading Amp daily cost/usage data.
    static func loadAmpDaily(
        range: CostUsageDayRange,
        now: Date,
        options: Options) -> CostUsageDailyReport
    {
        let root = Self.defaultAmpRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            return CostUsageDailyReport(data: [], summary: nil)
        }

        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        var cache = CostUsageCacheIO.load(
            provider: .amp,
            cacheRoot: options.cacheRoot,
            allTime: range.isAllTime)

        if options.forceRescan {
            cache = CostUsageCache()
        }

        var touched: Set<String> = []

        // Enumerate thread files
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        let threadFiles = contents.filter { $0.hasPrefix("T-") && $0.hasSuffix(".json") }

        for fileName in threadFiles {
            let filePath = root.appendingPathComponent(fileName).path
            let fileURL = URL(fileURLWithPath: filePath)
            touched.insert(filePath)

            let attrs = (try? fm.attributesOfItem(atPath: filePath)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let mtimeMs = Int64(mtime * 1000)

            guard size > 0 else { continue }

            // Check cache
            if let cached = cache.files[filePath],
               cached.mtimeUnixMs == mtimeMs,
               cached.size == size
            {
                continue // File unchanged, already in cache
            }

            // Remove old cached data if exists
            if let old = cache.files[filePath] {
                Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
            }

            // Parse file
            let parsed = Self.parseAmpFile(fileURL: fileURL, range: range)
            let usage = Self.makeFileUsage(
                mtimeUnixMs: mtimeMs,
                size: size,
                days: parsed.days,
                parsedBytes: size)
            cache.files[filePath] = usage
            Self.applyFileDays(cache: &cache, fileDays: usage.days, sign: 1)
        }

        // Remove stale files from cache
        for key in cache.files.keys where !touched.contains(key) {
            if let old = cache.files[key] {
                Self.applyFileDays(cache: &cache, fileDays: old.days, sign: -1)
            }
            cache.files.removeValue(forKey: key)
        }

        // Prune days outside range (for non-allTime caches)
        if !range.isAllTime {
            Self.pruneDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
        }

        cache.lastScanUnixMs = nowMs
        CostUsageCacheIO.save(provider: .amp, cache: cache, cacheRoot: options.cacheRoot, allTime: range.isAllTime)

        return Self.buildAmpReportFromCache(cache: cache, range: range)
    }

    /// Builds a CostUsageDailyReport from the Amp cache.
    private static func buildAmpReportFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange) -> CostUsageDailyReport
    {
        var entries: [CostUsageDailyReport.Entry] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreate = 0
        var totalTokens = 0
        var totalCost: Double = 0
        var costSeen = false
        let costScale = 1_000_000_000.0

        let dayKeys = cache.days.keys.sorted().filter {
            CostUsageDayRange.isInRange(dayKey: $0, since: range.sinceKey, until: range.untilKey)
        }

        for day in dayKeys {
            guard let models = cache.days[day] else { continue }
            let modelNames = models.keys.sorted()

            var dayInput = 0
            var dayOutput = 0
            var dayCacheRead = 0
            var dayCacheCreate = 0

            var breakdown: [CostUsageDailyReport.ModelBreakdown] = []
            var dayCost: Double = 0
            var dayCostSeen = false

            for model in modelNames {
                let packed = models[model] ?? [0, 0, 0, 0, 0]
                let input = packed[safe: 0] ?? 0
                let cacheRead = packed[safe: 1] ?? 0
                let cacheCreate = packed[safe: 2] ?? 0
                let output = packed[safe: 3] ?? 0
                let cachedCostNanos = packed[safe: 4] ?? 0

                dayInput += input
                dayCacheRead += cacheRead
                dayCacheCreate += cacheCreate
                dayOutput += output

                // Amp stores cost directly as credits (costNanos)
                let cost = cachedCostNanos > 0 ? Double(cachedCostNanos) / costScale : nil
                breakdown.append(CostUsageDailyReport.ModelBreakdown(modelName: model, costUSD: cost))
                if let cost {
                    dayCost += cost
                    dayCostSeen = true
                }
            }

            breakdown.sort { lhs, rhs in (rhs.costUSD ?? -1) < (lhs.costUSD ?? -1) }
            let top = Array(breakdown.prefix(3))

            let dayTotal = dayInput + dayCacheRead + dayCacheCreate + dayOutput
            let entryCost = dayCostSeen ? dayCost : nil
            entries.append(CostUsageDailyReport.Entry(
                date: day,
                inputTokens: dayInput,
                outputTokens: dayOutput,
                cacheReadTokens: dayCacheRead,
                cacheCreationTokens: dayCacheCreate,
                totalTokens: dayTotal,
                costUSD: entryCost,
                modelsUsed: modelNames,
                modelBreakdowns: top))

            totalInput += dayInput
            totalOutput += dayOutput
            totalCacheRead += dayCacheRead
            totalCacheCreate += dayCacheCreate
            totalTokens += dayTotal
            if let entryCost {
                totalCost += entryCost
                costSeen = true
            }
        }

        let summary: CostUsageDailyReport.Summary? = entries.isEmpty
            ? nil
            : CostUsageDailyReport.Summary(
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheCreationTokens: totalCacheCreate,
                totalTokens: totalTokens,
                totalCostUSD: costSeen ? totalCost : nil)

        return CostUsageDailyReport(data: entries, summary: summary)
    }
}
