import BadKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $model.preferences.trainingMinutes, in: 15...240, step: 15) {
                        LabeledContent("Trainingsdauer", value: Fmt.minutes(model.preferences.trainingMinutes))
                    }
                    Stepper(value: $model.preferences.changeMinutes, in: 0...45, step: 5) {
                        LabeledContent("Umziehen & Duschen", value: Fmt.minutes(model.preferences.changeMinutes))
                    }
                    Picker("Verkehrsmittel", selection: $model.preferences.travelMode) {
                        ForEach(TravelMode.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Mein Training")
                } footer: {
                    Text("Ein Bad gilt als machbar, wenn du vor Einlassschluss da bist und nach dem Umziehen noch deine Trainingsdauer bis zum Badeschluss schwimmen kannst.")
                }

                Section {
                    Toggle("Nur 50-m-Becken", isOn: Binding(
                        get: { model.preferences.minLaneLength == 50 },
                        set: { model.preferences.minLaneLength = $0 ? 50 : nil }))
                    Toggle("Eingeschränkte Wasserfläche zählt", isOn: $model.preferences.includeLimited)
                    Toggle("Volle Bäder ausblenden", isOn: $model.preferences.avoidCrowded)
                    Toggle("Frauenschwimmen zählt", isOn: $model.preferences.includeWomenOnly)
                    Toggle("Geschlossene Bäder zeigen", isOn: $model.preferences.showOutOfService)
                } header: {
                    Text("Bäder")
                } footer: {
                    Text("„Nur 50-m-Becken“ ist derselbe Filter wie der 50-m-Chip auf der Startseite. Geschlossene Bäder sind z. B. Sommerbäder außerhalb der Saison.")
                }

                Section("Nur Bäder mit …") {
                    ForEach(Feature.allCases.filter { $0 != .lane50 && $0 != .lane25 }) { f in
                        Toggle(isOn: Binding(
                            get: { model.preferences.requiredFeatures.contains(f) },
                            set: { on in
                                if on { model.preferences.requiredFeatures.insert(f) }
                                else { model.preferences.requiredFeatures.remove(f) }
                            })) {
                            Label(f.title, systemImage: f.symbol)
                        }
                    }
                }

                Section {
                    if let feed = model.feed {
                        LabeledContent("Stand", value: Fmt.weekdayClock(feed.generatedAt))
                        LabeledContent("Bäder", value: "\(feed.pools.count)")
                    }
                    Button("Jetzt aktualisieren", systemImage: "arrow.clockwise") {
                        Task { await model.refresh(force: true) }
                    }
                    .disabled(model.isRefreshing)
                    Link(destination: URL(string: "https://www.berlinerbaeder.de/baeder/")!) {
                        Label("berlinerbaeder.de", systemImage: "safari")
                    }
                } header: {
                    Text("Daten")
                } footer: {
                    Text("Inoffizielle App. Alle Angaben stammen von der Webseite der Berliner Bäder-Betriebe und sind ohne Gewähr.")
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var results: [SwimPlan] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.allPlans.sorted { $0.pool.name < $1.pool.name }
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.pool.name.lowercased().contains(q)
                || ($0.pool.district?.lowercased().contains(q) ?? false)
                || $0.pool.equipment.contains { $0.lowercased().contains(q) }
                || ($0.pool.type?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { plan in
                NavigationLink(value: plan.pool) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(plan.pool.name).foregroundStyle(.primary)
                            Text([plan.pool.type, plan.statusLine].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: plan.status.symbol).foregroundStyle(plan.status.color)
                    }
                }
            }
            .navigationTitle("Suche")
            .searchable(text: $query, prompt: "Bad, Bezirk, Ausstattung")
            .navigationDestination(for: Pool.self) { pool in
                PoolPager(plans: results, selected: pool)
            }
        }
    }
}

#if DEBUG
#Preview("Einstellungen") {
    SettingsScreen().environment(AppModel.preview()).preferredColorScheme(.dark)
}

#Preview("Suche") {
    SearchScreen().environment(AppModel.preview()).preferredColorScheme(.dark)
}
#endif
