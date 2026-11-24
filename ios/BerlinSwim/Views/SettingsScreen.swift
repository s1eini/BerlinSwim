import BadKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

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
                    Toggle("Nur ungeteilte Wasserfläche", isOn: $model.preferences.onlyFullWaterArea)
                    Toggle("Volle Bäder ausblenden", isOn: $model.preferences.avoidCrowded)
                    Toggle("Frauenschwimmen zählt", isOn: $model.preferences.includeWomenOnly)
                    Toggle("Geschlossene Bäder zeigen", isOn: $model.preferences.showOutOfService)
                } header: {
                    Text("Bäder")
                } footer: {
                    Text("„Nur 50-m-Becken“ ist derselbe Filter wie der 50-m-Chip auf der Startseite. Geschlossene Bäder sind z. B. Sommerbäder außerhalb der Saison. „Nur ungeteilte Wasserfläche“ blendet Zeiten aus, in denen Bahnen an Vereine vergeben sind.")
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
        }
        .readableContentMargins()
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
                            Text([plan.pool.type.map(siteTerm), plan.statusSentence].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: plan.status.symbol).foregroundStyle(plan.status.color)
                    }
                }
            }
            .readableContentMargins()
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

/// Readable width for Form/List on wide windows (iPad, unfolded foldables), the SwiftUI counterpart
/// of UIKit's readableContentGuide: insets only the scroll content via `contentMargins`, so the
/// navigation bar, its background, the title and the scroll indicator keep the full width.
/// Kicks in from 740 pt so the margin never drops below the list's own ~20 pt inset (otherwise the
/// content would get wider while the window grows). No effect on iPhone.
private struct ReadableContentMargins: ViewModifier {
    static let maxContentWidth: CGFloat = 700
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        let margin = (width - Self.maxContentWidth) / 2
        content
            .contentMargins(.horizontal, width >= Self.maxContentWidth + 40 ? margin : nil, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableContentMargins() -> some View { modifier(ReadableContentMargins()) }
}
