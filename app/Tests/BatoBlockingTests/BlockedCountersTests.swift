import Testing
@testable import BatoBlocking

struct BlockedCountersTests {
    @Test func countsPerPageAndResetsOnNewNavigation() {
        let counters = BlockedCounters()
        counters.recordBlocked(1)
        counters.recordBlocked(1)
        counters.recordBlocked(2)
        #expect(counters.count(for: 1) == 2)
        #expect(counters.count(for: 2) == 1)
        counters.pageStarted(1)
        #expect(counters.count(for: 1) == 0)
        #expect(counters.count(for: 2) == 1)
        counters.forget(2)
        #expect(counters.count(for: 2) == 0)
    }

    @Test func ignoresUnidentifiedBrowsersAndNotifiesObserver() {
        let counters = BlockedCounters()
        let seen = Recorder()
        counters.setObserver { seen.append($0, $1) }
        counters.recordBlocked(0)
        counters.recordBlocked(-3)
        counters.recordBlocked(7)
        counters.recordBlocked(7)
        #expect(seen.values == [[7, 1], [7, 2]])
    }

    @Test func concurrentRecordingLosesNoCounts() async {
        let counters = BlockedCounters()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { for _ in 0..<500 { counters.recordBlocked(5) } }
            }
        }
        #expect(counters.count(for: 5) == 4000)
    }
}

import Foundation

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[Int]] = []
    var values: [[Int]] { lock.withLock { stored } }
    func append(_ id: Int32, _ count: Int) { lock.withLock { stored.append([Int(id), count]) } }
}
