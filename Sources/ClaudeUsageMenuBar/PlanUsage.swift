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
    case claudeNotFound
    case commandFailed(String)
    case unparseable(String)
    /// `claude -p '/usage'` ran fine but its response omitted the percentages —
    /// observed when spawned as a plain headless subprocess (no controlling
    /// terminal), which is how a GUI app runs it. Distinct from `.unparseable`
    /// so the UI can explain it rather than show it as a generic parse failure.
    case noLiveNumbers

    var description: String {
        switch self {
        case .claudeNotFound: return "couldn't find the claude CLI in any known install location"
        case .commandFailed(let s): return "claude /usage failed: \(s)"
        case .unparseable(let s): return "could not parse /usage output: \(s.prefix(200))"
        case .noLiveNumbers: return "claude /usage ran but didn't include percentages this time"
        }
    }
}

/// Runs the actual `claude` CLI's `/usage` slash command — the same data
/// source Claude Code itself uses to render "Plan usage limits" — rather
/// than reverse-engineering an undocumented HTTP endpoint.
enum PlanUsageFetcher {
    /// Resolves `claude`'s binary path via plain filesystem checks — no shell,
    /// no `PATH` lookup. Two earlier approaches both leaked into things this app
    /// has no business touching: routing through `/bin/zsh -l` (to load PATH the
    /// way a terminal does) caused an unrelated "access files on a network
    /// volume" prompt, almost certainly from something in the user's shell
    /// startup files (.zprofile/.zshrc, oh-my-zsh, nvm, etc.) — that's a black
    /// box this app shouldn't be executing at all. Routing through AppleScript's
    /// `do shell script` caused unrelated Automation prompts (Photos, Music,
    /// Desktop access) — confirmed by removing the app and watching the prompts
    /// stop. Resolving the path ourselves and exec'ing `claude` directly (it's a
    /// native Mach-O binary, not a script) avoids both: no shell profile runs,
    /// no AppleScript, no PATH-search side effects.
    private static func resolveClaudeExecutable() -> URL? {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            for version in nodeVersions {
                candidates.append("\(home)/.nvm/versions/node/\(version)/bin/claude")
            }
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func fetch(completion: @escaping (Result<PlanUsageSnapshot, Error>) -> Void) {
        guard let claudeURL = resolveClaudeExecutable() else {
            completion(.failure(PlanUsageError.claudeNotFound))
            return
        }

        let process = Process()
        process.executableURL = claudeURL
        // --safe-mode: disables CLAUDE.md loading, skills, plugins, hooks, MCP
        // servers, custom commands/agents, output styles, workflows, and themes
        // — real-world testing showed macOS attributing a Photos/Music/Desktop/
        // network-volume access prompt to this app even with zero entitlements
        // and no shell involved, which only makes sense if it came from claude's
        // own background behavior (plugin sync, MCP server startup, etc. — see
        // `claude --help`'s description of --bare) running as our child process.
        // --safe-mode keeps auth working normally (confirmed: /usage still
        // returns full session/week percentages) while turning that off.
        // --no-chrome: belt-and-suspenders against its Chrome integration.
        // --tools "": disables all built-in tools — /usage is a local,
        // informational command (confirmed zero API/model cost) with no
        // legitimate reason to execute a tool at all.
        process.arguments = ["--safe-mode", "--no-chrome", "--tools", "", "-p", "/usage", "--output-format", "json"]
        // Minimal, explicit environment — no shell, no profile sourcing, so no
        // shell startup script can act on this app's behalf. `claude` itself
        // only needs HOME (to find ~/.claude) and a basic PATH for anything it
        // shells out to internally.
        process.environment = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Without this, `claude -p` waits ~3s for stdin before proceeding.
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
            if resultText.contains("using your subscription") {
                throw PlanUsageError.noLiveNumbers
            }
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
