import BadKit
import SwiftUI

@main
struct BerlinSwimApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
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
    @State private var tab: AppTab = .pools

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
        .sheet(item: Binding(
            get: { model.openPoolID.flatMap { id in model.pools.first { $0.id == id } } },
            set: { model.openPoolID = $0?.id }
        )) { pool in
            NavigationStack {
                PoolDetailView(pool: pool)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fertig", systemImage: "xmark") { model.openPoolID = nil }
                        }
                    }
            }
        }
    }
}
