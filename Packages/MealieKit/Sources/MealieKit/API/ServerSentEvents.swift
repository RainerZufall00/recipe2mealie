import Foundation

/// Progress events emitted by Mealie's `/create/*/stream` endpoints.
public enum ImportEvent: Equatable, Sendable {
    case progress(String)
    case done(slug: String)
    case failed(String)
}

/// Minimal parser for the `text/event-stream` format Mealie sends.
///
/// `URLSession.AsyncBytes.lines` drops blank lines, so an event is dispatched as soon as its
/// `data:` line arrives instead of waiting for the blank separator line.
struct ServerSentEventParser {
    private var eventName: String?

    mutating func consume(line: String) -> ImportEvent? {
        if line.isEmpty {
            eventName = nil
            return nil
        }
        if line.hasPrefix(":") { return nil } // keep-alive comment

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "event":
            eventName = String(value)
            return nil
        case "data":
            defer { eventName = nil }
            return Self.makeEvent(name: eventName ?? "message", data: String(value))
        default:
            return nil
        }
    }

    private struct Payload: Decodable {
        var message: String?
        var slug: String?
    }

    static func makeEvent(name: String, data: String) -> ImportEvent? {
        let payload = try? JSONDecoder().decode(Payload.self, from: Data(data.utf8))
        switch name {
        case "progress":
            return payload?.message.map(ImportEvent.progress)
        case "done":
            return payload?.slug.map { .done(slug: $0) }
        case "error":
            return .failed(payload?.message ?? data)
        default:
            return nil
        }
    }
}
