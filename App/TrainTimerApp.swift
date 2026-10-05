import SwiftUI

@main
struct TrainTimerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(arrivals: model.menuBarArrivals)
        }
        .menuBarExtraStyle(.window)
    }
}
