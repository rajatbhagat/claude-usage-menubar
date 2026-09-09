import Foundation

struct PlanUsageSnapshot {
    let sessionPercent: Int
    let sessionResetsAt: Date?
    let sessionResetRaw: String
    let weekPercent: Int?
    let weekResetsAt: Date?
    let weekResetRaw: String
}

enum PlanUsageError: Error, CustomStringConvertible {
    case commandFailed(String)
    case unparseable(String)

    var description: String {
        switch self {
        case .commandFailed(let s): return "claude /usage failed: \(s)"
        case .unparseable(let s): return "could not parse /usage output: \(s.prefix(200))"
        }
    }
}

/// Shells out to the actual `claude` CLI's `/usage` slash command — the same
/// data source Claude Code itself uses to render "Plan usage limits" — rather
/// than reverse-engineering an undocumented HTTP endpoint.
enum PlanUsageFetcher {
    static func fetch(completion: @escaping (Result<PlanUsageSnapshot, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Running `claude -p '/usage'` via a directly-spawned `/bin/zsh -l -c`
        // reliably gets an abbreviated response with no percentages (verified
        // against real output — not a guess). Routing it through AppleScript's
        // `do shell script`, which loads the user's login shell environment the
        // same way Terminal.app does, was the one invocation path that
        // consistently returned the full session/week numbers in testing.
        process.arguments = ["-e", "do shell script \"claude -p '/usage' --output-format json\""]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        process.terminationHandler = { proc in
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""

            guard proc.terminationStatus == 0, !out.isEmpty else {
                completion(.failure(PlanUsageError.commandFailed(err.isEmpty ? "exit \(proc.terminationStatus)" : err)))
                return
            }
            do {
                let snapshot = try parse(jsonOutput: out)
                completion(.success(snapshot))
            } catch {
                completion(.failure(error))
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    private static func parse(jsonOutput: String) throws -> PlanUsageSnapshot {
        guard let data = jsonOutput.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? String else {
            throw PlanUsageError.unparseable(jsonOutput)
        }
        return try parse(resultText: result)
    }

    static func parse(resultText: String) throws -> PlanUsageSnapshot {
        guard let session = extract(
            pattern: #"Current session:\s*(\d+)% used\s*·\s*resets\s*(.+?)\s*\(([^)]+)\)"#,
            in: resultText
        ) else {
            throw PlanUsageError.unparseable(resultText)
        }
        let week = extract(
            pattern: #"Current week \(all models\):\s*(\d+)% used\s*·\s*resets\s*(.+?)\s*\(([^)]+)\)"#,
            in: resultText
        )

        return PlanUsageSnapshot(
            sessionPercent: session.0,
            sessionResetsAt: parseResetDate(raw: session.1, timeZoneId: session.2),
            sessionResetRaw: session.1,
            weekPercent: week?.0,
            weekResetsAt: week.flatMap { parseResetDate(raw: $0.1, timeZoneId: $0.2) },
            weekResetRaw: week?.1 ?? ""
        )
    }

    private static func extract(pattern: String, in text: String) -> (Int, String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 4,
              let pctRange = Range(match.range(at: 1), in: text),
              let dateRange = Range(match.range(at: 2), in: text),
              let tzRange = Range(match.range(at: 3), in: text),
              let pct = Int(text[pctRange]) else { return nil }
        return (pct, String(text[dateRange]), String(text[tzRange]))
    }

    private static let monthLookup: [String: Int] = {
        let symbols = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var d = [String: Int]()
        for (i, s) in symbols.enumerated() { d[s] = i + 1 }
        return d
    }()

    /// Parses strings like "Sep 9 at 7:09pm" against an IANA zone id like "America/Chicago".
    private static func parseResetDate(raw: String, timeZoneId: String) -> Date? {
        let pattern = #"([A-Za-z]{3})\w*\s+(\d{1,2})\s+at\s+(\d{1,2}):(\d{2})\s*(am|pm)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges == 6 else { return nil }

        func group(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: raw) else { return "" }
            return String(raw[r])
        }

        guard let month = monthLookup[String(group(1).prefix(3).capitalized)],
              let day = Int(group(2)),
              var hour = Int(group(3)),
              let minute = Int(group(4)) else { return nil }

        let ampm = group(5).lowercased()
        if ampm == "pm" && hour != 12 { hour += 12 }
        if ampm == "am" && hour == 12 { hour = 0 }

        let timeZone = TimeZone(identifier: timeZoneId) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date()
        let currentYear = calendar.component(.year, from: now)

        var components = DateComponents()
        components.year = currentYear
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone

        guard var date = calendar.date(from: components) else { return nil }
        // Year boundary: a reset date that lands far in the past must be next year.
        if now.timeIntervalSince(date) > 86400 * 300 {
            components.year = currentYear + 1
            date = calendar.date(from: components) ?? date
        }
        return date
    }
}

func formatCountdown(to date: Date?) -> String {
    guard let date else { return "" }
    let interval = date.timeIntervalSinceNow
    if interval <= 0 { return "Resets soon" }
    let totalMinutes = Int(interval / 60)
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "Resets in \(days)d \(hours)h" }
    if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
    return "Resets in \(minutes)m"
}
