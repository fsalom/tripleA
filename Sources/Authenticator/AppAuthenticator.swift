import Foundation

public final class AppAuthenticator {
    private var storage: TokenStorageProtocol
    private var card: AuthenticationCardProtocol
    private var refreshTask: Task<String, Error>?

    public init(storage: TokenStorageProtocol,
                card: AuthenticationCardProtocol) {
        self.storage = storage
        self.card = card
    }

}

extension AppAuthenticator: AuthenticatorProtocol {
    public func get(token type: TokenType) async throws -> Token? {
        return switch type {
        case .access:
            storage.accessToken
        case .refresh:
            storage.refreshToken
        }
    }

    public func set(token: Token, for type: TokenType) async throws {
        switch type {
        case .access:
            storage.accessToken = token
        case .refresh:
            storage.accessToken = token
        }
    }

    // MARK: - validToken - check if token is valid or refresh token otherwise
    /**
     Return a valid token or try to get it from storage or remote data source

     - Returns: valid access token
     - Throws: An error of type `CustomError`  with extra info and show login screen
    */
    public func getCurrentToken() async throws -> String {
        if let accessToken = storage.accessToken {
            if accessToken.isValid {
                return accessToken.value
            } else if let refreshToken = storage.refreshToken, refreshToken.isValid {
                do {
                    return try await renewToken()
                } catch {
                    self.storage.removeAll()
                    throw AuthError.missingToken
                }
            }
        }
        try await logout()
        throw AuthError.refreshFailed
    }

    // MARK: - validToken - check if token is valid or refresh token otherwise
    /**
    Call to login if needed and get token

     - Throws: An error of type `CustomError`  with extra info
    */
    public func getNewToken(with parameters: [String : Any] = [:]) async throws {
        let tokens = try await card.getTokensWithLogin(with: parameters)
        self.storage.accessToken = tokens.accessToken
        self.storage.refreshToken = tokens.refreshToken
    }

    // MARK: - refreshToken - create a task and call refreshToken if needed
    /**
     Refresh token when is needed or logout
     - Returns: new refresh_token  `String`
     - Throws: An error of type `AuthError`
     */
    public func renewToken() async throws -> String {
        if let refreshTask = refreshTask {
            return try await refreshTask.value
        }
        let task = Task { () throws -> String in
            defer { refreshTask = nil }
            guard let refreshToken = storage.refreshToken?.value else {
                throw AuthError.tokenNotFound
            }
            do {
                let tokens = try await card.getNewTokens(with: refreshToken)
                self.storage.accessToken = tokens.accessToken
                self.storage.refreshToken = tokens.refreshToken
                return tokens.accessToken.value
            } catch {
                try await self.logout()
                throw AuthError.refreshFailed
            }
        }
        self.refreshTask = task
        return try await task.value
    }

    // MARK: - logout
    /**
     Remove data and go to start view controller
     */
    public func logout() async throws {
        try await card.logout()
        self.storage.removeAll()
    }
}
