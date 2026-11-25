import BadKit
import CoreLocation
import SwiftUI

extension AppModel {
    /// Toggle binding for one required feature (Sauna, Barrierefrei, …), shared by the filter menu and Settings.
    func featureBinding(_ feature: Feature) -> Binding<Bool> {
        Binding(
            get: { self.preferences.requiredFeatures.contains(feature) },
            set: { on in
                if on { self.preferences.requiredFeatures.insert(feature) }
                else { self.preferences.requiredFeatures.remove(feature) }
            })
    }

    /// "Nur 50-m-Becken": the same lane-length minimum the 50 m chip and Settings use.
    var only50mBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.minLaneLength == 50 },
            set: { self.preferences.minLaneLength = $0 ? 50 : nil })
    }

    /// The map's recenter button only helps with a known position in the Berlin area (60 km around the city
    /// centre). Without location, or from Munich, it would not be useful.
    var canRecenterOnUser: Bool {
        guard travelKnown else { return false }
        let o = origin
        let c = Geo.berlinCenter
        return CLLocation(latitude: o.lat, longitude: o.lon)
            .distance(from: CLLocation(latitude: c.lat, longitude: c.lon)) < 60_000
    }

    /// Whether any toggle-style filter (not travel mode / duration, which are always set) is on.
    var hasActiveFilters: Bool {
        preferences.minLaneLength == 50 || !preferences.requiredFeatures.isEmpty || preferences.avoidCrowded
    }
}

/// The filter chips of the pool list as a "…" menu, for the map sheet's toolbar.
/// Changes apply live; the menu stays open so several filters can be changed in one go.
struct FilterMenu: View {
    @Environment(AppModel.self) private var model

    private let quick: [Feature] = [.sauna, .accessible]

    var body: some View {
        @Bindable var model = model
        Menu {
            // Submenus keep the menu short; the heading makes clear the times are the training duration.
            Section("Mein Training") {
                if model.travelKnown {
                    Menu("Anreise", systemImage: model.preferences.travelMode.symbol) {
                        Picker("Verkehrsmittel", selection: $model.preferences.travelMode) {
                            ForEach(TravelMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                Menu("Trainingsdauer", systemImage: "timer") {
                    Picker("Trainingsdauer", selection: $model.preferences.trainingMinutes) {
                        ForEach([30, 45, 60, 75, 90, 120], id: \.self) { Text(Fmt.minutes($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            Section("Filter") {
                Toggle("50 m", systemImage: "figure.pool.swim", isOn: model.only50mBinding)
                ForEach(quick) { f in
                    Toggle(f.title, systemImage: f.symbol, isOn: model.featureBinding(f))
                }
                Toggle("Nicht voll", systemImage: "person.2.slash", isOn: $model.preferences.avoidCrowded)
            }
        } label: {
            Image(systemName: "ellipsis")
                .overlay(alignment: .topTrailing) { // a filter is on: the chips are hidden, so show it here
                    if model.hasActiveFilters {
                        Circle().fill(.orange).frame(width: 9, height: 9).offset(x: 5, y: -5)
                    }
                }
        }
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("Filter")
        .accessibilityValue(model.hasActiveFilters ? Text("aktiv") : Text(""))
    }
}
