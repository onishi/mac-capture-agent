import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Kinds of secrets and personal data. The detected value itself is never
/// returned, stored or logged — only its kind and location.
public enum SensitiveKind: String, Sendable, CaseIterable, Equatable {
    case privateKey
    case awsAccessKey
    case githubToken
    case slackToken
    case googleAPIKey
    case stripeKey
    case llmAPIKey
    case jwt
    case creditCard
    case password
    case email
    case phoneNumber

    /// High severity triggers a warning during screen sharing.
    public var isHighSeverity: Bool {
        switch self {
        case .email, .phoneNumber: return false
        default: return true
        }
    }

    public var label: String {
        switch self {
        case .privateKey: return "Private key"
        case .awsAccessKey: return "AWS access key"
        case .githubToken: return "GitHub token"
        case .slackToken: return "Slack token"
        case .googleAPIKey: return "Google API key"
        case .stripeKey: return "Stripe key"
        case .llmAPIKey: return "API key"
        case .jwt: return "Access token (JWT)"
        case .creditCard: return "Credit card number"
        case .password: return "Password"
        case .email: return "Email address"
        case .phoneNumber: return "Phone number"
        }
    }

    public var japaneseLabel: String {
        switch self {
        case .privateKey: return "秘密鍵"
        case .awsAccessKey: return "AWS アクセスキー"
        case .githubToken: return "GitHub トークン"
        case .slackToken: return "Slack トークン"
        case .googleAPIKey: return "Google API キー"
        case .stripeKey: return "Stripe キー"
        case .llmAPIKey: return "API キー"
        case .jwt: return "アクセストークン（JWT）"
        case .creditCard: return "クレジットカード番号"
        case .password: return "パスワード"
        case .email: return "メールアドレス"
        case .phoneNumber: return "電話番号"
        }
    }
}

public struct SensitiveFinding: Sendable, Equatable {
    public let kind: SensitiveKind
    /// Normalized, top-left-origin rect of the text block containing it.
    public let region: CGRect?
}

/// Regex + checksum detection of secrets in recognized text.
public struct SensitiveDataDetector: Sendable {
    private static let patterns: [(SensitiveKind, String)] = [
        (.privateKey, #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY-----"#),
        (.awsAccessKey, #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
        (.githubToken, #"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})\b"#),
        (.slackToken, #"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"#),
        (.googleAPIKey, #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
        (.stripeKey, #"\b(?:sk|rk)_live_[0-9A-Za-z]{20,}\b"#),
        (.llmAPIKey, #"\bsk-(?:ant-|proj-)?[A-Za-z0-9_\-]{24,}\b"#),
        (.jwt, #"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b"#),
        (.password, #"(?i)\b(?:password|passwd|pwd|パスワード)\s*[:=：]\s*\S{4,}"#),
        (.email, #"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"#),
        (.phoneNumber, #"(?:\+81[\s\-]?|\b0)\d{1,4}[\s\-]\d{1,4}[\s\-]\d{3,4}\b|\(\d{3}\)\s?\d{3}-\d{4}\b"#)
    ]

    private static let cardCandidate = #"\b(?:\d[ \-]?){13,19}\b"#

    public init() {}

    /// Kinds found in `text` (each kind at most once).
    public func kinds(in text: String) -> [SensitiveKind] {
        var result: [SensitiveKind] = []
        for (kind, pattern) in Self.patterns where text.range(of: pattern, options: .regularExpression) != nil {
            result.append(kind)
        }
        if containsCardNumber(text) { result.append(.creditCard) }
        return result
    }

    public func findings(in regions: [RecognizedTextRegion]) -> [SensitiveFinding] {
        regions.flatMap { region in kinds(in: region.text).map { SensitiveFinding(kind: $0, region: region.boundingBox) } }
    }

    /// Splits regions into those safe to process (translate, archive, send)
    /// and the findings in the others. Regions with *any* sensitive data are excluded.
    public func partition(_ regions: [RecognizedTextRegion]) -> (safe: [RecognizedTextRegion], findings: [SensitiveFinding]) {
        var safe: [RecognizedTextRegion] = []
        var findings: [SensitiveFinding] = []
        for region in regions {
            let kinds = kinds(in: region.text)
            if kinds.isEmpty {
                safe.append(region)
            } else {
                findings += kinds.map { SensitiveFinding(kind: $0, region: region.boundingBox) }
            }
        }
        return (safe, findings)
    }

    func containsCardNumber(_ text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: Self.cardCandidate, options: .regularExpression, range: searchRange) {
            let digits = text[range].compactMap { $0.wholeNumberValue }
            if (13...19).contains(digits.count), Self.luhn(digits), Set(digits).count > 1 {
                return true
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
