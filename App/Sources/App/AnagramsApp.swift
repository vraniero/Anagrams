import SwiftUI

@main
struct AnagramsApp: App {
    @State private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
