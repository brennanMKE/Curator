import Foundation
import Testing
@testable import Curator

struct PlexErrorTests {
    @Test func atsBlockIsExplained() {
        #expect(PlexError(URLError(.appTransportSecurityRequiresSecureConnection)) == .insecureConnectionBlocked)
    }

    @Test func cancellationIsItsOwnCase() {
        #expect(PlexError(URLError(.cancelled)) == .cancelled)
    }

    @Test func connectionFailuresAreUnreachable() {
        guard case .unreachable = PlexError(URLError(.cannotFindHost)) else {
            Issue.record("expected .unreachable")
            return
        }
    }

    @Test func everyErrorHasAMessageAndSuggestion() {
        let all: [PlexError] = [.notConfigured, .invalidServerURL, .unauthorized, .insecureConnectionBlocked, .unreachable("x"), .http(500), .badResponse, .cancelled]
        for error in all {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }
}
