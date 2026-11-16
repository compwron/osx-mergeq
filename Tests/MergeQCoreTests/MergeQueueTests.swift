import XCTest
@testable import MergeQCore

final class QueueParserTests: XCTestCase {
    private func json(_ entries: String, viewer: String = "me") -> Data {
        """
        {"data":{"viewer":{"login":"\(viewer)"},"repository":{"mergeQueue":{
          "url":"https://github.com/o/r/queue/master",
          "entries":{"nodes":[\(entries)]}}}}}
        """.data(using: .utf8)!
    }

    private func node(_ position: Int, _ eta: String, author: String, number: Int) -> String {
        """
        {"position":\(position),"state":"AWAITING_CHECKS","estimatedTimeToMerge":\(eta),
         "pullRequest":{"number":\(number),"title":"PR \(number)","url":"https://x/\(number)","author":{"login":"\(author)"}}}
        """
    }

    func testParsesEntriesSortedByPosition() throws {
        let snapshot = try QueueParser.parse(json([
            node(2, "600", author: "a", number: 2),
            node(1, "300", author: "b", number: 1),
        ].joined(separator: ",")))

        XCTAssertEqual(snapshot.entries.map(\.number), [1, 2])
        XCTAssertEqual(snapshot.queueURL, "https://github.com/o/r/queue/master")
    }

    func testHeadlineUsesMyPrWhenQueued() throws {
        let snapshot = try QueueParser.parse(json([
            node(1, "300", author: "other", number: 1),
            node(2, "600", author: "me", number: 2),
            node(3, "900", author: "other", number: 3),
        ].joined(separator: ",")))

        XCTAssertEqual(snapshot.myFirstEntry?.number, 2)
        XCTAssertEqual(snapshot.headlineSeconds, 600)
        XCTAssertEqual(snapshot.secondsUntilQueueClears, 900)
    }

    func testHeadlineFallsBackToQueueClearTime() throws {
        let snapshot = try QueueParser.parse(json([
            node(1, "300", author: "other", number: 1),
            node(2, "null", author: "other", number: 2),
        ].joined(separator: ",")))

        XCTAssertNil(snapshot.myFirstEntry)
        XCTAssertEqual(snapshot.headlineSeconds, 300)
    }

    func testEmptyQueue() throws {
        let snapshot = try QueueParser.parse(json(""))

        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertNil(snapshot.headlineSeconds)
    }

    func testMissingQueueThrows() {
        let body = #"{"data":{"viewer":{"login":"me"},"repository":{"mergeQueue":null}}}"#.data(using: .utf8)!

        XCTAssertThrowsError(try QueueParser.parse(body)) { error in
            XCTAssertEqual(error as? QueueParseError, .noMergeQueue)
        }
    }

    func testGraphQLErrorsThrow() {
        let body = #"{"data":null,"errors":[{"message":"Bad credentials"}]}"#.data(using: .utf8)!

        XCTAssertThrowsError(try QueueParser.parse(body)) { error in
            XCTAssertEqual(error.localizedDescription, "Bad credentials")
        }
    }
}

final class DurationFormatterTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(DurationFormatter.short(nil), "?")
        XCTAssertEqual(DurationFormatter.short(30), "<1m")
        XCTAssertEqual(DurationFormatter.short(299), "5m")
        XCTAssertEqual(DurationFormatter.short(3600), "1h")
        XCTAssertEqual(DurationFormatter.short(4320), "1h 12m")
    }
}

extension QueueParseError: Equatable {
    public static func == (lhs: QueueParseError, rhs: QueueParseError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
