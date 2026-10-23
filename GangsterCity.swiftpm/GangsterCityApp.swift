import SwiftUI

@main
struct GangsterCityApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @State private var engine: GameEngine?

    var body: some View {
        if let engine {
            GameView(engine: engine) {
                self.engine = nil
            }
        } else {
            TitleView { save in
                engine = GameEngine(save: save)
            }
        }
    }
}
