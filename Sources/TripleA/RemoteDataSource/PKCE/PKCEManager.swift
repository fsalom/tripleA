import UIKit
import AuthenticationServices
import CommonCrypto

public final class PKCEManager: NSObject {
    private var storage: StorageProtocol!
    private let SSO: Bool
    private let config: PKCEConfig!
    weak var presentationAnchor: ASPresentationAnchor?

    private var codeVerifier: String = ""

    public init(storage: StorageProtocol,
                presentationAnchor: ASPresentationAnchor?,
                SSO: Bool = true,
                config: PKCEConfig) {
        self.storage = storage
        self.presentationAnchor = presentationAnchor
        self.SSO = !SSO
        self.config = config
    }

    // MARK: - getCodeVerifier - Generate code verifier needed in authentication flow
    /**
     Generate code verifier needed in authentication flow
     - Returns: new code verifier  `String`
     */
    private func getCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEscapedEncodedString()
    }

    // MARK: - getCodeChallenge - Generate code challenge with SHA256 encryptation
    /**
     return a code challenge based on code verifier
     - Returns: encrypted code verifiear with SHA256  `String`
     */
    private func getCodeChallenge(for codeVerifier: String) -> String? {
        guard let data = codeVerifier.data(using: .utf8) else { return nil }
        var buffer2 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &buffer2)
        }
        let hash = Data(buffer2)
        return hash.base64URLEscapedEncodedString()
    }
}

extension PKCEManager: RemoteDataSourceProtocol {
    // MARK: - showLogin - initialize authentication flow with ASWebAuthenticationSession
    /**
     return a code for PKCE flow
     - Returns: code generated by authority
     */
    public func showLogin(completion: @escaping (String?) -> Void) {
        codeVerifier = getCodeVerifier()
        let queryItems = [URLQueryItem(name: "next", value: "/auth/authorize?client_id=\(config.clientID)&code_challenge_method=\(config.codeChallengeMethod)&response_type=\(config.responseType)&scope=\(config.scope)&code_challenge=\(getCodeChallenge(for: codeVerifier) ?? "")")]
        guard var authURL = URLComponents(string: config.authorizeURL) else { return }
        authURL.queryItems = queryItems
        if let finalURL = authURL.url {
            Log.thisURL(finalURL)
        }
        let scheme = config.callbackURLScheme

        guard let url = authURL.url else { return }
        guard let callback = URL(string: scheme) else { return }

        DispatchQueue.main.async {
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callback.scheme) { callbackURL, error in
                guard error == nil, let callbackURL = callbackURL else {
                    completion(nil)
                    return
                }
                guard let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                      let queryItems = urlComponents.queryItems else {
                    completion(nil)
                    return
                }
                for queryItem in queryItems {
                    if(queryItem.name == "code"){
                        completion(queryItem.value)
                        return
                    }
                }
                completion(nil)
            }
            session.prefersEphemeralWebBrowserSession = self.SSO
            session.presentationContextProvider = self
            session.start()
        }
    }

    // MARK: - getAccessToken - get access token or initialize authentication flow
    /**
     get access token from storage or initialize authentication flow
     - Returns: valid access token `String`
     */
    public func getAccessToken(with parameters: [String : Any]) async throws -> String {
        if let accessToken = storage.accessToken {
            if accessToken.isValid {
                return accessToken.value
            } else {
                if let refreshToken = storage.refreshToken {
                    if refreshToken.isValid {
                        do {
                            return try await self.getRefreshToken(with: refreshToken.value)
                        } catch {
                            throw AuthError.badRequest
                        }
                    }
                }
            }
        }
        do {
            let code = await withCheckedContinuation { continuation in
                self.showLogin(completion: { code in
                    continuation.resume(returning: code)
                })
            }
            if code != nil {
                return try await getToken(with: code)
            } else {
                return try await getAccessToken(with: parameters)
            }
        } catch {
            throw AuthError.badRequest
        }
    }

    // MARK: - getToken - Call authority with code challenge to get access and refresh tokens
    /**
     - Returns: new access token  `String`
     */
    private func getToken(with code: String?) async throws -> String {
        guard let code else { throw NetworkError.invalidResponse }
        let parameters = [
            "grant_type": "authorization_code",
            "client_id": self.config.clientID,
            "client_secret": self.config.clientSecret,
            "code": code,
            "redirect_uri": self.config.callbackURLScheme,
            "code_verifier": self.codeVerifier,
        ]

        let endpoint = Endpoint(path: self.config.tokenURL,
                                httpMethod: .post,
                                parameters: parameters)

        let tokens = try await self.load(endpoint: endpoint, of: TokensDTO.self)
        storage.accessToken = Token(value: tokens.accessToken, expireInt: tokens.expiresIn)
        storage.refreshToken = Token(value: tokens.refreshToken, expireInt: nil)
        return tokens.accessToken
    }

    public func getRefreshToken(with refreshToken: String) async throws -> String {
        return ""
    }

    // MARK: - logout
    /**
     Remove storage and initialize authenticatin flow
     */
    public func logout() async {
        Task {
            let success = await withCheckedContinuation { continuation in
                logoutHandler { success in
                    continuation.resume(returning: success)
                }
            }
            if success {
                self.storage.removeAll()
                await try? self.getAccessToken(with: [:])
            }
        }
    }

    // MARK: - logout with ASWebAuthenticationSession
    /**
     Remove storage and initialize authenticatin flow
     */
    func logoutHandler(success: @escaping (Bool) -> Void) {
        guard let callback = URL(string: config.callbackURLLogoutScheme) else {
            success(false)
            return
        }
        let queryItems = [URLQueryItem(name: "redirect_uri", value: config.callbackURLLogoutScheme)]
        guard var logoutURL = URLComponents(string: config.logoutURL) else {
            success(false)
            return
        }
        logoutURL.queryItems = queryItems
        if let finalURL = logoutURL .url {
            Log.thisURL(finalURL)
        }
        DispatchQueue.main.async {
            let session = ASWebAuthenticationSession(url: logoutURL.url!, callbackURLScheme: callback.scheme) { response, error in
                guard error == nil else {
                    success(false)
                    return
                }

                success(true)
            }
            session.prefersEphemeralWebBrowserSession = self.SSO
            session.presentationContextProvider = self
            session.start()
        }
    }

    func load<T: Decodable>(endpoint: Endpoint, of type: T.Type, allowRetry: Bool = true) async throws -> T {
        Log.thisCall(endpoint.request)
        let (data, urlResponse) = try await URLSession.shared.data(for: endpoint.request)
        guard let response = urlResponse as? HTTPURLResponse else{
            throw NetworkError.invalidResponse
        }
        Log.thisResponse(response, data: data)
        let decoder = JSONDecoder()
        let parseData = try decoder.decode(T.self, from: data)
        return parseData
    }
}

extension PKCEManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor ?? ASPresentationAnchor()
    }
}

fileprivate extension Data {
    func base64URLEscapedEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

