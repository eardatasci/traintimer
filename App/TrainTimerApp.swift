import SwiftUI

@main
struct TrainTimerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            HStack {
                Image(systemName: "tram.fill")
                if let summary = model.menuBarSummary {
                    Text(summary)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
