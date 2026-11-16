import Foundation

public struct QueueEntry: Equatable {
    public let position: Int
    public let state: String
    public let estimatedSecondsToMerge: Int?
    public let number: Int
    public let title: String
    public let author: String
    public let url: String

    public var isMine: Bool = false
}

public struct QueueSnapshot: Equatable {
    public let queueURL: String
    public let viewer: String
    public let entries: [QueueEntry]

    /// Your own first PR in the queue, if any — that's the merge time you care about.
    public var myFirstEntry: QueueEntry? {
        entries.first(where: { $0.isMine })
    }

    /// Time until the last entry lands, i.e. the whole queue drains.
    public var secondsUntilQueueClears: Int? {
        entries.compactMap(\.estimatedSecondsToMerge).max()
    }

    /// The ETA shown in the menu bar: your PR if it's queued, otherwise the whole queue.
    public var headlineSeconds: Int? {
        myFirstEntry?.estimatedSecondsToMerge ?? secondsUntilQueueClears
    }
}

public enum QueueQuery {
    public static let graphQL = """
    query($owner: String!, $name: String!) {
      viewer { login }
      repository(owner: $owner, name: $name) {
        mergeQueue {
          url
          entries(first: 100) {
            nodes {
              position
              state
              estimatedTimeToMerge
              pullRequest { number title url author { login } }
            }
          }
        }
      }
    }
    """
}

public enum QueueParseError: Error, LocalizedError {
    case noMergeQueue
    case graphQL(String)

    public var errorDescription: String? {
        switch self {
        case .noMergeQueue: return "Repo has no merge queue on its default branch"
        case .graphQL(let message): return message
        }
    }
}

public enum QueueParser {
    private struct Response: Decodable {
        struct GQLError: Decodable { let message: String }
        struct Data: Decodable {
            struct Viewer: Decodable { let login: String }
            struct Repository: Decodable {
                struct MergeQueue: Decodable {
                    struct Entries: Decodable { let nodes: [Node] }
                    struct Node: Decodable {
                        struct PR: Decodable {
                            struct Author: Decodable { let login: String }
                            let number: Int
                            let title: String
                            let url: String
                            let author: Author?
                        }
                        let position: Int
                        let state: String
                        let estimatedTimeToMerge: Int?
                        let pullRequest: PR?
                    }
                    let url: String
                    let entries: Entries
                }
                let mergeQueue: MergeQueue?
            }
            let viewer: Viewer
            let repository: Repository?
        }
        let data: Data?
        let errors: [GQLError]?
    }

    public static func parse(_ json: Foundation.Data) throws -> QueueSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: json)
        if let errors = response.errors, !errors.isEmpty {
            throw QueueParseError.graphQL(errors.map(\.message).joined(separator: "; "))
        }
        guard let data = response.data, let queue = data.repository?.mergeQueue else {
            throw QueueParseError.noMergeQueue
        }
        let viewer = data.viewer.login
        let entries = queue.entries.nodes
            .compactMap { node -> QueueEntry? in
                guard let pr = node.pullRequest else { return nil }
                let author = pr.author?.login ?? "ghost"
                return QueueEntry(
                    position: node.position,
                    state: node.state,
                    estimatedSecondsToMerge: node.estimatedTimeToMerge,
                    number: pr.number,
                    title: pr.title,
                    author: author,
                    url: pr.url,
                    isMine: author == viewer
                )
            }
            .sorted { $0.position < $1.position }
        return QueueSnapshot(queueURL: queue.url, viewer: viewer, entries: entries)
    }
}

public enum DurationFormatter {
    public static func short(_ seconds: Int?) -> String {
        guard let seconds else { return "?" }
        if seconds < 60 { return "<1m" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

public enum StateLabel {
    public static func readable(_ state: String) -> String {
        switch state {
        case "AWAITING_CHECKS": return "checks running"
        case "MERGEABLE": return "ready to merge"
        case "UNMERGEABLE": return "unmergeable"
        case "QUEUED": return "queued"
        case "LOCKED": return "locked"
        default: return state.lowercased()
        }
    }
}
