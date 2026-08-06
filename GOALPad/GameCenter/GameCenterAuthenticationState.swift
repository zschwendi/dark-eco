//
//  GameCenterAuthenticationState.swift
//  GOALPad
//

import Foundation

enum GameCenterAccessPointContext: Equatable, Sendable {
    case unknown
    case launcher
    case gameplay
}

struct GameCenterAuthenticationState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case authenticating
        case authenticated
        case signedOut
        case unavailable
    }

    let phase: Phase
    let playerName: String?
    let message: String

    func enablesAccessPoint(in context: GameCenterAccessPointContext) -> Bool {
        phase == .authenticated && context == .launcher
    }

    static let idle = GameCenterAuthenticationState(
        phase: .idle,
        playerName: nil,
        message: "Game Center has not started."
    )

    static let authenticating = GameCenterAuthenticationState(
        phase: .authenticating,
        playerName: nil,
        message: "Signing in to Game Center."
    )

    static func resolved(
        isAuthenticated: Bool,
        playerName: String?,
        errorDescription: String?
    ) -> GameCenterAuthenticationState {
        if isAuthenticated {
            let message = playerName.map { "Signed in to Game Center as \($0)." }
                ?? "Signed in to Game Center."
            return GameCenterAuthenticationState(
                phase: .authenticated,
                playerName: playerName,
                message: message
            )
        }

        if let errorDescription, !errorDescription.isEmpty {
            return GameCenterAuthenticationState(
                phase: .unavailable,
                playerName: nil,
                message: errorDescription
            )
        }

        return GameCenterAuthenticationState(
            phase: .signedOut,
            playerName: nil,
            message: "Game Center is signed out."
        )
    }
}
