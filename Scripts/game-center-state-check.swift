import Foundation

@main
private struct GameCenterStateCheck {
    private static var failures = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            print("  ok   \(message)")
        } else {
            print("  FAIL \(message)")
            failures += 1
        }
    }

    static func main() {
        print("Game Center state enables platform UI only for an authenticated player")
        check(!GameCenterAuthenticationState.idle.enablesAccessPoint(in: .launcher),
              "the idle state keeps the access point disabled")
        check(!GameCenterAuthenticationState.authenticating.enablesAccessPoint(in: .launcher),
              "authentication keeps the access point disabled")

        let authenticated = GameCenterAuthenticationState.resolved(
            isAuthenticated: true,
            playerName: "Test Player",
            errorDescription: nil
        )
        check(authenticated.phase == .authenticated,
              "successful authentication reports an authenticated state")
        check(authenticated.playerName == "Test Player"
              && authenticated.message == "Signed in to Game Center as Test Player.",
              "successful authentication reports the player name")
        check(!authenticated.enablesAccessPoint(in: .unknown),
              "an authenticated player stays hidden until the app reports its context")
        check(authenticated.enablesAccessPoint(in: .launcher),
              "an authenticated player enables the access point in the launcher")
        check(!authenticated.enablesAccessPoint(in: .gameplay),
              "gameplay keeps the authenticated access point hidden")

        let signedOut = GameCenterAuthenticationState.resolved(
            isAuthenticated: false,
            playerName: nil,
            errorDescription: nil
        )
        check(signedOut.phase == .signedOut
              && signedOut.message == "Game Center is signed out.",
              "a declined sign-in degrades to a quiet signed-out state")
        check(!signedOut.enablesAccessPoint(in: .launcher),
              "a signed-out player cannot expose the access point")

        let unavailable = GameCenterAuthenticationState.resolved(
            isAuthenticated: false,
            playerName: nil,
            errorDescription: "Game Center is unavailable for this account."
        )
        check(unavailable.phase == .unavailable
              && unavailable.message == "Game Center is unavailable for this account.",
              "a localized authentication error remains available to the app")
        check(!unavailable.enablesAccessPoint(in: .launcher),
              "an authentication error cannot expose the access point")

        if failures > 0 {
            print("Game Center state check failed: \(failures) assertion(s)")
            exit(1)
        }

        print("Game Center state check passed")
    }
}
