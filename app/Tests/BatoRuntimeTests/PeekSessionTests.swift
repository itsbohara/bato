import Foundation
import Testing
@testable import BatoRuntime

struct PeekSessionTests {
    private let url = URL(string: "https://example.invalid/start")!

    private func pages() -> (LivePage, LivePage) {
        let profile = UUID()
        return (LivePage(entryID: UUID(), profileID: profile), LivePage(entryID: UUID(), profileID: profile))
    }

    @Test func linkEligibilityRejectsUnsafeOrMalformedDestinations() {
        for value in ["https://example.invalid/hello?q=one%20two", "http://localhost:18765/", "https://[::1]/", "https://example.invalid./"] {
            #expect(PeekSession.isEligibleLink(URL(string: value)!))
        }
        for value in ["/relative", "about:blank", "javascript:alert(1)", "file:///tmp/page", "https://user:password@example.invalid/", "https://example.invalid:0/", "https://example.invalid:65536/", "https://bad..invalid/", "https://-bad.invalid/", "https://bad_.invalid/", "https://.invalid/", "https://[bad]/"] {
            #expect(!PeekSession.isEligibleLink(URL(string: value)!))
        }
        #expect(!PeekSession.isEligibleLink(URL(string: "child", relativeTo: url)!))
    }

    @Test func openingRequiresDistinctPagesInSameProfileAndNeverReplacesOccupiedPreview() throws {
        let (parent, page) = pages()
        var session = PeekSession()
        let mutation1 = !session.open(parent: parent, page: LivePage(entryID: UUID(), profileID: UUID()), url: url)
        #expect(mutation1)
        let mutation2 = !session.open(parent: parent, page: LivePage(entryID: parent.entryID, profileID: parent.profileID), url: url)
        #expect(mutation2)
        let mutation3 = !session.open(parent: parent, page: page, url: URL(string: "about:blank")!)
        #expect(mutation3)
        #expect(session.preview == nil)
        let mutation4 = session.open(parent: parent, page: page, url: url)
        #expect(mutation4)
        let original = try #require(session.preview)
        let mutation5 = !session.open(parent: parent, page: LivePage(entryID: UUID(), profileID: parent.profileID), url: url)
        #expect(mutation5)
        #expect(session.preview == original)
    }

    @Test func dismissalWaitsForConfirmationAndCancellationAllowsPromotion() throws {
        let (parent, page) = pages()
        var session = PeekSession()
        let mutation6 = session.open(parent: parent, page: page, url: url)
        #expect(mutation6)
        let mutation7 = session.requestDismissal() == page
        #expect(mutation7)
        #expect(session.preview?.isPendingDismissal == true)
        let mutation8 = session.requestDismissal() == nil
        #expect(mutation8)
        #expect(session.preparePromotion() == nil)
        #expect(session.preview?.page == page)
        let mutation9 = session.handle(.closeCancelled(page))
        #expect(mutation9)
        #expect(session.preview?.isPendingDismissal == false)
        let prepared = try #require(session.preparePromotion())
        #expect(prepared.page == page)
        let mutation10 = session.completePromotion(prepared)
        #expect(mutation10)
        #expect(session.preview == nil)
    }

    @Test func promotionRetainsLiveIdentityAndLatestNavigationWithoutRecreatingPage() throws {
        let (parent, page) = pages()
        var session = PeekSession()
        let mutation11 = session.open(parent: parent, page: page, url: url, title: "Initial")
        #expect(mutation11)
        let destination = URL(string: "https://example.invalid/redirected")!
        let mutation12 = session.handle(.navigation(page, url: destination, title: "Updated"))
        #expect(mutation12)
        let promoted = try #require(session.preparePromotion())
        #expect(session.preview?.page == page)
        let mutation13 = session.completePromotion(promoted)
        #expect(mutation13)
        #expect(promoted.page == page)
        #expect(promoted.parent == parent)
        #expect(promoted.url == destination)
        #expect(promoted.title == "Updated")
        #expect(session.preparePromotion() == nil)
        let mutation14 = !session.handle(.closed(page))
        #expect(mutation14)
    }

    @Test func failedAdoptionAndStalePreparationKeepPreviewOwned() throws {
        let (parent, page) = pages()
        var session = PeekSession()
        let mutation15 = session.open(parent: parent, page: page, url: url)
        #expect(mutation15)
        let prepared = try #require(session.preparePromotion())
        // A failed host save simply does not complete the prepared transfer.
        #expect(session.preview == prepared)
        let errorURL = URL(string: "chrome-error://chromewebdata/")!
        let mutation16 = session.handle(.navigation(page, url: errorURL, title: "Error"))
        #expect(mutation16)
        let mutation17 = !session.completePromotion(prepared)
        #expect(mutation17)
        let latest = try #require(session.preparePromotion())
        #expect(latest.url == errorURL)
        let mutation18 = session.requestDismissal() == page
        #expect(mutation18)
        let mutation19 = !session.completePromotion(latest)
        #expect(mutation19)
        let mutation20 = session.handle(.closeCancelled(page))
        #expect(mutation20)
        let mutation21 = !session.completePromotion(latest)
        #expect(mutation21)
        let refreshed = try #require(session.preparePromotion())
        let mutation22 = session.completePromotion(refreshed)
        #expect(mutation22)
        let mutation23 = !session.completePromotion(refreshed)
        #expect(mutation23)
    }

    @Test func returningToSameNavigationDoesNotReviveOldPromotionPreparation() throws {
        let (parent, page) = pages()
        var session = PeekSession()
        let mutation24 = session.open(parent: parent, page: page, url: url, title: "Initial")
        #expect(mutation24)
        let original = try #require(session.preparePromotion())
        let mutation25 = session.handle(.navigation(page, url: URL(string: "https://example.invalid/next")!, title: "Next"))
        #expect(mutation25)
        let mutation26 = session.handle(.navigation(page, url: url, title: "Initial"))
        #expect(mutation26)
        let mutation27 = !session.completePromotion(original)
        #expect(mutation27)
        #expect(session.preview?.page == page)
        let mutation28 = session.completePromotion(try #require(session.preparePromotion()))
        #expect(mutation28)
    }

    @Test func staleGenerationAndParentEventsCannotMutateOrClosePreview() throws {
        let (parent, page) = pages()
        let stale = LivePage(entryID: page.entryID, profileID: page.profileID)
        var session = PeekSession()
        let mutation29 = session.open(parent: parent, page: page, url: url)
        #expect(mutation29)
        let mutation30 = session.requestDismissal() == page
        #expect(mutation30)
        let original = try #require(session.preview)
        for other in [stale, parent] {
            let mutation31 = !session.handle(.navigation(other, url: URL(string: "https://example.invalid/stale")!, title: "Stale"))
            #expect(mutation31)
            let mutation32 = !session.handle(.closed(other))
            #expect(mutation32)
            let mutation33 = !session.handle(.creationFailed(other))
            #expect(mutation33)
            let mutation34 = !session.handle(.unloaded(other))
            #expect(mutation34)
            let mutation35 = !session.handle(.closeCancelled(other))
            #expect(mutation35)
        }
        #expect(session.preview == original)
        let mutation36 = session.handle(.closed(page))
        #expect(mutation36)
        #expect(session.preview == nil)
    }

    @Test func terminalEventsReleaseSlotAndLatePreviousCallbacksCannotAffectNextPreview() {
        let (parent, page) = pages()
        for terminal in [PageEvent.closed(page), .creationFailed(page), .unloaded(page)] {
            var session = PeekSession()
            let mutation37 = session.open(parent: parent, page: page, url: url)
            #expect(mutation37)
            let mutation38 = session.handle(terminal)
            #expect(mutation38)
            #expect(session.preview == nil)
            let replacement = LivePage(entryID: page.entryID, profileID: page.profileID)
            let mutation39 = session.open(parent: parent, page: replacement, url: url)
            #expect(mutation39)
            let mutation40 = !session.handle(terminal)
            #expect(mutation40)
            #expect(session.preview?.page == replacement)
        }
    }
}
