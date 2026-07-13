import SwiftUI
import SwiftData

@main
struct AubadeApp: App {
    let container = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { PresetCategories.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}
