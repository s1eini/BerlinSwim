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

    /// Training length / travel mode as optionals: nil = not chosen (no filter).
    var trainingBinding: Binding<Int?> {
        Binding(
            get: { self.preferences.trainingSet ? self.preferences.trainingMinutes : nil },
            set: { if let v = $0 { self.preferences.trainingMinutes = v } else { self.preferences.trainingSet = false } })
    }

    var travelBinding: Binding<TravelMode?> {
        Binding(
            get: { self.preferences.travelSet ? self.preferences.travelMode : nil },
            set: { if let v = $0 { self.preferences.travelMode = v } else { self.preferences.travelSet = false } })
    }

    /// "Nur 50-m-Becken": the same lane-length minimum the 50 m chip and Settings use.
    var only50mBinding: Binding<Bool> {
        Binding(
            get: { self.preferences.minLaneLength == 50 },
            set: { self.preferences.minLaneLength = $0 ? 50 : nil })
    }

    /// Wished swim lengths offered in the pickers (home screen, map menu, Settings).
    static let trainingOptions = [15, 30, 45, 60, 75, 90, 120]

    /// The map's recenter button only helps with a known position in the Berlin area.
    var canRecenterOnUser: Bool { travelKnown }

    /// Whether any toggle-style filter (not travel mode / duration, which are always set) is on.
    var hasActiveFilters: Bool {
        preferences.minLaneLength == 50 || !preferences.requiredFeatures.isEmpty || (travelKnown && (preferences.trainingSet || preferences.travelSet))
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
            if model.travelKnown { // swim length / travel only make sense with a usable position
            Section("Mein Training") {
                if model.travelKnown {
                    Menu("Anreise", systemImage: model.preferences.travelSet ? model.preferences.travelMode.symbol : "figure.walk.motion") {
                        Picker("Anreise", selection: model.travelBinding) {
                            Text("Beliebig").tag(TravelMode?.none)
                            ForEach(TravelMode.allCases) { Label($0.title, systemImage: $0.symbol).tag(TravelMode?.some($0)) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                Menu("Schwimmdauer", systemImage: "figure.pool.swim") {
                    Picker("Schwimmdauer", selection: model.trainingBinding) {
                        Text("Beliebig").tag(Int?.none)
                        ForEach(AppModel.trainingOptions, id: \.self) { Text(Fmt.minutes($0)).tag(Int?.some($0)) }
                    }
                    .pickerStyle(.inline)
                }
            }
            }
            Section("Filter") {
                Toggle("50 m", systemImage: "ruler.fill", isOn: model.only50mBinding)
                ForEach(quick) { f in
                    Toggle(f.title, systemImage: f.symbol, isOn: model.featureBinding(f))
                }
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
