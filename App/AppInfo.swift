import AppKit

enum AppInfo {
    static let repository = URL(string: "https://github.com/eardatasci/traintimer")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/eardatasci/traintimer/releases/latest")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    @MainActor
    static func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: "Live arrivals from the MTA's GTFS-Realtime feeds.\nNot affiliated with or endorsed by the MTA.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        credits.append(NSAttributedString(
            string: repository.absoluteString.replacingOccurrences(of: "https://", with: ""),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: repository]
        ))
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        // Menu bar apps aren't frontmost, so the panel would open behind other windows.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
