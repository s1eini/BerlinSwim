import BadKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// "0.1.0 (1)" – marketing version and build number.
    static let version: String = {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }()

    /// Ko-fi link from Info.plist (`SUPPORT_URL` in project.yml); empty = row hidden.
    static let supportURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "SupportURL") as? String)
        .flatMap { $0.isEmpty ? nil : URL(string: $0) }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if model.travelKnown { // travel and swim length need a usable position (Berlin area)
                    Section {
                        Picker("Anreise", selection: model.travelBinding) {
                            Text("Beliebig").tag(TravelMode?.none)
                            ForEach(TravelMode.allCases) { Text($0.title).tag(TravelMode?.some($0)) }
                        }
                        // Menu picker like the other rows: stays on one line (a stepper pushes the label onto two)
                        Picker("Umziehen & Duschen", selection: $model.preferences.changeMinutes) {
                            ForEach(Set([0, 5, 10, 15, 20, 25, 30, 45, model.preferences.changeMinutes]).sorted(), id: \.self) {
                                Text(Fmt.minutes($0)).tag($0)
                            }
                        }
                        Picker("Schwimmdauer", selection: model.trainingBinding) {
                            Text("Beliebig").tag(Int?.none)
                            ForEach(AppModel.trainingOptions, id: \.self) { Text(Fmt.minutes($0)).tag(Int?.some($0)) }
                        }
                    } header: {
                        Text("Mein Training")
                    } footer: {
                        Text("Ein Bad gilt als machbar, wenn du vor Einlassschluss da bist und nach dem Umziehen noch deine Schwimmdauer bis zum Badeschluss schwimmen kannst. Ohne Auswahl zählt jedes offene Bad, sortiert nach Nähe.")
                    }
                } else {
                    Section {
                        Text(model.tooFarFromBerlin
                             ? "Du bist nicht in Berlin. Anreise und Schwimmdauer sind ausgeblendet, die Bäder nach Öffnungszeit sortiert."
                             : model.locationPending
                             ? "Der Standort wird noch ermittelt. Anreise und Schwimmdauer erscheinen, sobald er da ist."
                             : "Dein Standort ist nicht geteilt. Anreise und Schwimmdauer sind ausgeblendet, die Bäder nach Öffnungszeit sortiert.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if model.locationDenied {
                            Button("Standort freigeben") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    } header: {
                        Text("Mein Training")
                    }
                }

                Section {
                    // 50 m first (lane length, not a Feature), then the equipment features – same as the chips on the home screen
                    Toggle(isOn: model.only50mBinding) {
                        Label("Mit 50-m-Becken", systemImage: "ruler.fill")
                    }
                    ForEach(Feature.allCases) { f in
                        Toggle(isOn: model.featureBinding(f)) {
                            Label(f.title, systemImage: f.symbol)
                        }
                    }
                } header: {
                    Text("Nur Bäder mit …")
                }

                Section {
                    Toggle("Nur ungeteilte Wasserfläche", isOn: $model.preferences.onlyFullWaterArea)
                    Toggle("Inkl. Frauenschwimmen", isOn: $model.preferences.includeWomenOnly)
                    Toggle("Volle Bäder ausblenden", isOn: $model.preferences.avoidCrowded)
                    Toggle("Geschlossene Bäder zeigen", isOn: $model.preferences.showOutOfService)
                } header: {
                    Text("Weitere Optionen")
                } footer: {
                    Text("Geschlossene Bäder sind z. B. Sommerbäder außerhalb der Saison. „Nur ungeteilte Wasserfläche“ blendet Zeiten aus, in denen Bahnen an Vereine vergeben sind.")
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
                }

                Section {
                    Text("Inoffizielle App. Alle Angaben stammen von der Webseite der Berliner Bäder-Betriebe und sind ohne Gewähr.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LabeledContent("Version", value: Self.version)
                    if let support = Self.supportURL {
                        Link(destination: support) {
                            Label("Kaffee spendieren (Ko-fi)", systemImage: "cup.and.heat.waves")
                        }
                    }
                } header: {
                    Text("Über")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
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
                Button {
                    // Same path as a widget tap: switches to "Bäder", pushes the detail, closes the sheet.
                    model.openPoolID = plan.pool.id
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(plan.pool.name).foregroundStyle(.primary)
                            Text([plan.pool.type.map(siteTerm), plan.statusSentence].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: plan.status.symbol).foregroundStyle(plan.status.color)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain) // keep the row text neutral instead of tinted like a button
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bad, Bezirk, Ausstattung")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
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
