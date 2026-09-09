import Foundation

/// Incrementally tails every `*.jsonl` file under ~/.claude/projects, only reading
/// the bytes appended since the last scan so repeated scans stay cheap even as
/// session logs grow across a long-running Claude Code session.
final class LogScanner {
    private let projectsDir: URL
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso8601NoFraction = ISO8601DateFormatter()

    private var fileOffsets: [String: UInt64] = [:]
    private var lineBuffers: [String: Data] = [:]

    init(projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")) {
        self.projectsDir = projectsDir
    }

    func scan() -> [UsageEvent] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var events: [UsageEvent] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            events.append(contentsOf: readNewLines(from: url))
        }
        return events
    }

    private func readNewLines(from url: URL) -> [UsageEvent] {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = (attrs[.size] as? NSNumber)?.uint64Value else { return [] }

        let previousOffset = fileOffsets[path] ?? 0
        if fileSize < previousOffset {
            // File was truncated or rotated; restart from the top.
            fileOffsets[path] = 0
            lineBuffers[path] = nil
        }
        let offset = fileOffsets[path] ?? 0
        guard fileSize > offset else { return [] }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        handle.seek(toFileOffset: offset)
        let newData = handle.readDataToEndOfFile()
        fileOffsets[path] = fileSize

        var buffer = lineBuffers[path] ?? Data()
        buffer.append(newData)

        var events: [UsageEvent] = []
        let newline: UInt8 = 0x0A
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            if let event = parseLine(lineData) {
                events.append(event)
            }
        }
        lineBuffers[path] = buffer
        return events
    }

    private func parseLine(_ data: Data) -> UsageEvent? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String,
              let timestampStr = obj["timestamp"] as? String,
              let timestamp = parseDate(timestampStr) else { return nil }

        let sessionId = (obj["sessionId"] as? String) ?? (obj["session_id"] as? String) ?? "unknown"
        let dedupKey = (obj["requestId"] as? String) ?? (obj["uuid"] as? String) ?? UUID().uuidString

        return UsageEvent(
            timestamp: timestamp,
            sessionId: sessionId,
            model: model,
            inputTokens: (usage["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage["output_tokens"] as? Int) ?? 0,
            cacheCreationTokens: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheReadTokens: (usage["cache_read_input_tokens"] as? Int) ?? 0,
            dedupKey: dedupKey
        )
    }

    private func parseDate(_ s: String) -> Date? {
        iso8601.date(from: s) ?? iso8601NoFraction.date(from: s)
    }
}
