import Foundation

/// A dotted numeric version like "1.2.0", optionally written as a "v1.2.0" tag.
public struct ReleaseVersion: Sendable, Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        components = parts.map { $0! }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = lhs.component(at: index), right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    private func component(at index: Int) -> Int {
        index < components.count ? components[index] : 0
    }
}

/// The subset of GitHub's "latest release" API response we need.
/// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
public struct LatestRelease: Sendable, Decodable {
    public let tag: String
    public let url: URL

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case url = "html_url"
    }

    public var version: ReleaseVersion? { ReleaseVersion(tag) }

    public func isNewer(than currentVersion: String) -> Bool {
        guard let version, let current = ReleaseVersion(currentVersion) else { return false }
        return version > current
    }
}
