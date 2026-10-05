import SwiftUI
import TrainTimerCore

struct MenuContentView: View {
    let model: AppModel
    /// A ScrollView in a MenuBarExtra window has no height of its own, so size it to its content.
    @State private var listHeight: CGFloat = 0
    private let maxListHeight = min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 100)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 340)
        .task { await model.refreshIfStale(olderThan: 15) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.locationStatus {
        case .locating:
            message("Finding your location…", showsProgress: true)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text("Location access is off").font(.headline)
                Text("Train Timer needs your location to find nearby stations.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Location Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
            .padding(14)
        case .located where model.stations.isEmpty:
            message("No subway stations within \(Int(AppModel.searchRadius / 1000)) km.")
        case .located where model.lastUpdated == nil:
            if model.failedFeeds.failed > 0 {
                message("Can't reach the MTA. Retrying…", showsProgress: true)
            } else {
                message("Loading train times…", showsProgress: true)
            }
        case .located:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.boards.enumerated()), id: \.element.id) { index, board in
                        if index > 0 { Divider().padding(.horizontal, 14) }
                        StationSection(board: board, now: model.now)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            // `.never` rather than `.hidden`: macOS keeps "hidden" indicators visible when a mouse is connected.
            .scrollIndicators(.never)
            .frame(height: min(listHeight, maxListHeight))
        }
    }

    private func message(_ text: String, showsProgress: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView().controlSize(.small) }
            Text(text).foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.failedFeeds.failed > 0 {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(model.failedFeeds.failed == model.failedFeeds.requested ? "Can't reach the MTA" : "Some lines didn't update")
            }
            if let updated = model.lastUpdated {
                Text("Updated \(Text(updated, style: .relative)) ago")
            }
            Spacer()
            if let update = model.availableUpdate {
                Button("Update to \(update.version?.description ?? update.tag)") { NSWorkspace.shared.open(update.url) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Menu {
                Button("Refresh Now") { Task { await model.refresh() } }
                Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                Divider()
                Button("About Train Timer") { AppInfo.showAboutPanel() }
                Button("Quit Train Timer") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct StationSection: View {
    let board: StationBoard
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(board.station.name).font(.headline)
                Spacer()
                Text("\(board.station.walkingMinutes) min walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if board.groups.isEmpty {
                Text("No trains in the next hour")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(board.groups) { group in
                HStack(spacing: 8) {
                    RouteBullet(style: RouteStyle(routeID: group.routeID))
                    Text(group.destinationName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    times(group.times)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// "2, 7, 12 min", with trains you can't walk to in time dimmed.
    private func times(_ times: [Date]) -> some View {
        let parts = times.enumerated().map { index, time -> Text in
            let label = StationBoard.minutesLabel(until: time, now: now).replacingOccurrences(of: "m", with: "")
            let text = Text(label).foregroundStyle(board.isCatchable(time, now: now) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            return index == 0 ? text : Text(", ").foregroundStyle(.tertiary) + text
        }
        return (parts.reduce(Text(""), +) + Text(" min").foregroundStyle(.secondary))
            .monospacedDigit()
            .help("Dimmed trains leave before you could walk there (\(board.station.walkingMinutes) min).")
    }
}
