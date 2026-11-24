import BadKit
import SwiftUI

@main
struct BerlinSwimApp: App {
    @State private var model: AppModel = {
        #if DEBUG
        // Screenshot aid: `-previewHour 23` runs on the bundled seed data at a fixed time (no network/location).
        let hour = UserDefaults.standard.integer(forKey: "previewHour")
        if hour > 0 { return AppModel.preview(hour: hour) }
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

enum AppTab: Hashable { case pools, map, settings, search }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = {
        #if DEBUG
        // Screenshot aid: `-tab settings|map|search`
        switch UserDefaults.standard.string(forKey: "tab") {
        case "settings": return .settings
        case "map": return .map
        case "search": return .search
        default: break
        }
        #endif
        return .pools
    }()

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Bäder", systemImage: "figure.pool.swim", value: .pools) {
                PoolListScreen()
            }
            Tab("Karte", systemImage: "map", value: .map) {
                PoolMapScreen()
            }
            Tab("Einstellungen", systemImage: "slider.horizontal.3", value: .settings) {
                SettingsScreen()
            }
            Tab(value: .search, role: .search) {
                SearchScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: model.openPoolID, initial: true) { openFromDeepLink() }
        .onChange(of: model.pools.count) { openFromDeepLink() }
    }

    /// Widget tap / deep link: switch to the pools tab and push the detail.
    private func openFromDeepLink() {
        guard let id = model.openPoolID, let pool = model.pools.first(where: { $0.id == id }) else { return }
        tab = .pools
        model.poolPath = [pool]
        model.openPoolID = nil
    }
}
