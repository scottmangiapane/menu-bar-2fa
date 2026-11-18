import Foundation
import SwiftOTP

enum TOTPAlgorithm: String, Codable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var swiftOTPAlgorithm: OTPAlgorithm {
        switch self {
        case .sha1: return .sha1
        case .sha256: return .sha256
        case .sha512: return .sha512
        }
    }
}

struct TOTPConfiguration: Codable {
    var algorithm: TOTPAlgorithm
    var digits: Int
    var period: Int

    static let standard = TOTPConfiguration(algorithm: .sha1, digits: 6, period: 30)

    init(algorithm: TOTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm, digits, period
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decodeIfPresent(TOTPAlgorithm.self, forKey: .algorithm) ?? .sha1
        digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 6
        period = try container.decodeIfPresent(Int.self, forKey: .period) ?? 30

        guard digits == 6 || digits == 8 else {
            throw DecodingError.dataCorruptedError(
                forKey: .digits,
                in: container,
                debugDescription: "TOTP codes must contain 6 or 8 digits."
            )
        }
        guard period > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .period,
                in: container,
                debugDescription: "TOTP period must be greater than zero."
            )
        }
    }
}

struct OTPAccount: Codable, Identifiable {
    let id: UUID
    var name: String
    var secret: String
    var configuration: TOTPConfiguration

    init(
        id: UUID = UUID(),
        name: String,
        secret: String,
        configuration: TOTPConfiguration = .standard
    ) {
        self.id = id
        self.name = name
        self.secret = secret
        self.configuration = configuration
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, secret, configuration
    }

    // Older multi-account data did not include TOTP settings. Treat it as the
    // interoperable default so existing installations continue to work.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        secret = try container.decode(String.self, forKey: .secret)
        configuration = try container.decodeIfPresent(TOTPConfiguration.self, forKey: .configuration) ?? .standard
    }
}

struct TOTPProvisioningInfo {
    let secret: String
    let issuer: String?
    let configuration: TOTPConfiguration
}
