import BadKit
import SwiftUI

@main
struct BerlinSwimApp: App {
    @State private var model: AppModel = {
        #if DEBUG
        // Screenshot aid: `-previewHour 23` runs on the bundled seed data at a fixed time (no network/location).
        let hour = UserDefaults.standard.integer(forKey: "previewHour")
        // Chosen swim length and travel mode, so the screenshots show the filled chips and travel times.
        if hour > 0 { return AppModel.preview(hour: hour) { $0.trainingMinutes = 60; $0.travelMode = .transit } }
        #endif
        return AppModel()
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark) // white text on water backgrounds needs dark glass
                .task {
                    #if DEBUG
                    // Screenshot/testing aid: launch with `-openPool <id>`.
                    let id = UserDefaults.standard.integer(forKey: "openPool")
                    if id > 0 { model.openPoolID = id }
                    #endif
                    await model.start()
                }
                .onOpenURL { url in
                    // berlinswim://pool/<id>
                    if url.host() == "pool", let id = Int(url.lastPathComponent) {
                        model.openPoolID = id
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

enum AppSheet: String, Identifiable {
    case map, settings, search
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PoolListScreen()
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .map:
                    PoolMapScreen()
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                case .settings:
                    SettingsScreen()
                        .presentationDetents([.large])
                case .search:
                    SearchScreen()
                        .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                #if DEBUG
                // Screenshot aid: `-sheet map|settings|search`
                if let s = UserDefaults.standard.string(forKey: "sheet") { model.sheet = AppSheet(rawValue: s) }
                #endif
            }
            .onChange(of: model.openPoolID, initial: true) { openFromDeepLink() }
            .onChange(of: model.pools.count) { openFromDeepLink() }
    }

    /// Widget tap / deep link / search or map selection: close any sheet and push the detail.
    private func openFromDeepLink() {
        guard let id = model.openPoolID, let pool = model.pools.first(where: { $0.id == id }) else { return }
        model.sheet = nil
        model.poolPath = [pool]
        model.openPoolID = nil
    }
}
