import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AmpStatusSnapshot: Sendable {
    public let creditsSpentToday: Double
    public let creditsSpentTotal: Double
    public let tokensToday: Int
    public let tokensTotal: Int
    public let threadsToday: Int
    public let threadsTotal: Int
    public let updatedAt: Date

    /// Daily grant amount in credits (Amp provides $10/day free).
    public static let dailyGrantCredits: Double = 10.0

    /// Replenishment rate: $0.42 per hour.
    public static let replenishmentPerHour: Double = 0.42

    /// Credits remaining today ($10 - spent).
    public var creditsRemainingToday: Double {
        max(0, Self.dailyGrantCredits - self.creditsSpentToday)
    }

    /// Average credits per thread (all time).
    public var averageCreditsPerThread: Double? {
        guard self.threadsTotal > 0 else { return nil }
        return self.creditsSpentTotal / Double(self.threadsTotal)
    }

    /// Average tokens per thread (all time).
    public var averageTokensPerThread: Int? {
        guard self.threadsTotal > 0 else { return nil }
        return self.tokensTotal / self.threadsTotal
    }

    /// Converts Amp usage to a unified UsageSnapshot.
    /// Returns nil for primary/secondary to hide percentage bars.
    /// Amp uses custom credits display instead.
    public func toUsageSnapshot() -> UsageSnapshot {
        // Don't show percentage bars for Amp - they're misleading for credit model
        let identity = ProviderIdentitySnapshot(
            providerID: .amp,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "\(self.threadsToday) today / \(self.threadsTotal) total threads")

        return UsageSnapshot(
            primary: nil,
            secondary: nil,
            ampCredits: AmpCreditsSnapshot(
                remainingToday: self.creditsRemainingToday,
                spentToday: self.creditsSpentToday,
                spentTotal: self.creditsSpentTotal,
                tokensToday: self.tokensToday,
                tokensTotal: self.tokensTotal,
                threadsToday: self.threadsToday,
                threadsTotal: self.threadsTotal,
                averageCreditsPerThread: self.averageCreditsPerThread,
                averageTokensPerThread: self.averageTokensPerThread),
            updatedAt: self.updatedAt,
            identity: identity)
    }

    /// Hours until daily grant fully replenishes.
    public var hoursUntilFullReplenishment: Double {
        guard self.creditsSpentToday > 0 else { return 0 }
        return self.creditsSpentToday / Self.replenishmentPerHour
    }
}

public enum AmpStatusProbeError: LocalizedError, Sendable, Equatable {
    case ampNotInstalled
    case noThreadsDirectory
    case noThreadsFound
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .ampNotInstalled:
            "Amp CLI is not installed or not on PATH."
        case .noThreadsDirectory:
            "Amp threads directory not found. Run 'amp' to create your first thread."
        case .noThreadsFound:
            "No Amp threads found yet."
        case let .parseFailed(msg):
            "Could not parse Amp threads: \(msg)"
        }
    }
}

public struct AmpStatusProbe: Sendable {
    public static let threadsPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.local/share/amp/threads"
    }()

    private static let log = TokenStatsLog.logger("amp-probe")

    public init() {}

    public func fetch() async throws -> AmpStatusSnapshot {
        let fm = FileManager.default

        guard fm.fileExists(atPath: Self.threadsPath) else {
            throw AmpStatusProbeError.noThreadsDirectory
        }

        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: Self.threadsPath)
        } catch {
            throw AmpStatusProbeError.parseFailed("Cannot read threads directory: \(error.localizedDescription)")
        }

        let threadFiles = contents.filter { $0.hasPrefix("T-") && $0.hasSuffix(".json") }

        guard !threadFiles.isEmpty else {
            throw AmpStatusProbeError.noThreadsFound
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var creditsSpentToday: Double = 0
        var creditsSpentTotal: Double = 0
        var tokensToday: Int = 0
        var tokensTotal: Int = 0
        var threadsToday = 0
        var threadsTotal = 0

        for fileName in threadFiles {
            let filePath = "\(Self.threadsPath)/\(fileName)"
            guard let data = fm.contents(atPath: filePath) else { continue }

            do {
                let thread = try Self.parseThread(data: data)
                threadsTotal += 1

                // Check if thread was created today
                let threadDate = Date(timeIntervalSince1970: thread.created / 1000)
                let isToday = calendar.isDate(threadDate, inSameDayAs: todayStart) ||
                    threadDate >= todayStart

                if isToday {
                    threadsToday += 1
                }

                // Sum credits and tokens from all messages with usage data
                for message in thread.messages {
                    if let usage = message.usage {
                        let messageTokens = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
                        tokensTotal += messageTokens
                        if isToday {
                            tokensToday += messageTokens
                        }

                        if let credits = usage.credits {
                            // Amp stores credits in cents - convert to USD
                            let usd = credits / 100.0
                            creditsSpentTotal += usd
                            if isToday {
                                creditsSpentToday += usd
                            }
                        }
                    }
                }
            } catch {
                Self.log.warning("Failed to parse thread \(fileName): \(error)")
                continue
            }
        }

        Self.log.info("Amp probe complete", metadata: [
            "creditsSpentToday": "\(creditsSpentToday)",
            "creditsSpentTotal": "\(creditsSpentTotal)",
            "tokensToday": "\(tokensToday)",
            "tokensTotal": "\(tokensTotal)",
            "threadsToday": "\(threadsToday)",
            "threadsTotal": "\(threadsTotal)",
        ])

        return AmpStatusSnapshot(
            creditsSpentToday: creditsSpentToday,
            creditsSpentTotal: creditsSpentTotal,
            tokensToday: tokensToday,
            tokensTotal: tokensTotal,
            threadsToday: threadsToday,
            threadsTotal: threadsTotal,
            updatedAt: Date())
    }

    // MARK: - Thread JSON Parsing

    private struct AmpThread: Decodable {
        let id: String
        let created: Double // epoch milliseconds
        let messages: [AmpMessage]
    }

    private struct AmpMessage: Decodable {
        let role: String
        let usage: AmpUsage?
    }

    private struct AmpUsage: Decodable {
        let model: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let credits: Double?
    }

    private static func parseThread(data: Data) throws -> AmpThread {
        let decoder = JSONDecoder()
        return try decoder.decode(AmpThread.self, from: data)
    }
}
