import Foundation
import SwiftOTP

enum TOTPProvisioning {
    static func parse(_ value: String) -> TOTPProvisioningInfo? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp" else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard let rawSecret = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("secret") == .orderedSame
        })?.value else {
            return nil
        }

        let rawAlgorithm = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("algorithm") == .orderedSame
        })?.value?.uppercased() ?? "SHA1"
        guard let algorithm = TOTPAlgorithm(rawValue: rawAlgorithm) else {
            return nil
        }

        let digits: Int
        if let rawDigits = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("digits") == .orderedSame
        })?.value {
            guard let parsedDigits = Int(rawDigits), parsedDigits == 6 || parsedDigits == 8 else {
                return nil
            }
            digits = parsedDigits
        } else {
            digits = 6
        }

        let period: Int
        if let rawPeriod = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("period") == .orderedSame
        })?.value {
            guard let parsedPeriod = Int(rawPeriod), parsedPeriod > 0 else {
                return nil
            }
            period = parsedPeriod
        } else {
            period = 30
        }

        let secret = normalizedSecret(from: rawSecret)
        guard base32DecodeToData(secret) != nil else {
            return nil
        }

        // Prefer the issuer parameter. The URI label may also include an issuer
        // prefix, which is the compatibility fallback when the parameter is absent.
        let queryIssuer = queryItems.first(where: {
            $0.name.caseInsensitiveCompare("issuer") == .orderedSame
        })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelParts = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: ":", maxSplits: 1)
        let labelIssuer = labelParts.count == 2
            ? String(labelParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let issuer = queryIssuer?.isEmpty == false ? queryIssuer : labelIssuer

        return TOTPProvisioningInfo(
            secret: secret,
            issuer: issuer?.isEmpty == false ? issuer : nil,
            configuration: TOTPConfiguration(algorithm: algorithm, digits: digits, period: period)
        )
    }

    static func normalizedSecret(from input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }
}
