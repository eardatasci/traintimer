import Foundation
import Testing
@testable import TrainTimerCore

struct ReleaseVersionTests {
    @Test func parsesTagsWithOrWithoutPrefix() {
        #expect(ReleaseVersion("v1.2.3")?.components == [1, 2, 3])
        #expect(ReleaseVersion("1.2")?.components == [1, 2])
        #expect(ReleaseVersion("v1.2-beta") == nil)
        #expect(ReleaseVersion("") == nil)
    }

    @Test func comparesNumericallyAndIgnoresTrailingZeros() throws {
        let v = { (string: String) throws -> ReleaseVersion in try #require(ReleaseVersion(string)) }
        #expect(try v("1.10.0") > v("1.9.9"))
        #expect(try v("2.0") > v("1.99"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try !(v("1.0.0") < v("1.0")))
    }
}

struct LatestReleaseTests {
    private let json = Data("""
    {"tag_name": "v1.1.0", "html_url": "https://github.com/eardatasci/traintimer/releases/tag/v1.1.0", "draft": false}
    """.utf8)

    @Test func offersNewerReleases() throws {
        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        #expect(release.version == ReleaseVersion("1.1.0"))
        #expect(release.url.absoluteString == "https://github.com/eardatasci/traintimer/releases/tag/v1.1.0")
        #expect(release.isNewer(than: "1.0.0"))
        #expect(!release.isNewer(than: "1.1"))
        #expect(!release.isNewer(than: "1.2.0"))
        #expect(!release.isNewer(than: "garbage"))
    }
}
