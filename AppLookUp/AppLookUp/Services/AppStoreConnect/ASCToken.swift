import CryptoKit
import Foundation

// MARK: - Token

/// App Store Connect wants a short-lived ES256 JWT signed with your API key.
enum ASCToken {

    static func make(issuerID: String, keyID: String, privateKey: String) throws -> String {
        let key = try signingKey(from: privateKey)

        // Back-date slightly for clock skew; Apple caps a token's life at 20 minutes.
        let now = Int(Date.now.timeIntervalSince1970)
        let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now - 30,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        ]

        let encodedHeader = base64URL(try JSONSerialization.data(withJSONObject: header, options: .sortedKeys))
        let encodedPayload = base64URL(try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        // JWT's ES256 wants the raw 64-byte r‖s signature, which is exactly rawRepresentation.
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    /// Accepts the .p8 file as-is, or just its base64 body.
    static func signingKey(from text: String) throws -> P256.Signing.PrivateKey {
        let body = text
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .filter { !$0.isWhitespace }

        guard !body.isEmpty else { throw ASCError.badPrivateKey }

        if let der = Data(base64Encoded: body),
           let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return key
        }
        let pem = "-----BEGIN PRIVATE KEY-----\n\(body)\n-----END PRIVATE KEY-----"
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return key
        }
        throw ASCError.badPrivateKey
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

