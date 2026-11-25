import BadKit
import MapKit
import SwiftUI

struct PoolMapScreen: View {
    @Environment(AppModel.self) private var model
    private static let berlinRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.505, longitude: 13.40),
        span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.42))
    private static let userOrBerlin: MapCameraPosition = .userLocation(fallback: .region(berlinRegion))
    @State private var position: MapCameraPosition = Self.userOrBerlin
    @State private var selection: Int?
    @Namespace private var mapScope

    var body: some View {
        NavigationStack {
        Map(position: $position, selection: $selection, scope: mapScope) {
            UserAnnotation()
            ForEach(model.plans.reversed()) { plan in
                if let lat = plan.pool.lat, let lon = plan.pool.lon {
                    Annotation(plan.pool.shortName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        PoolPin(plan: plan, selected: selection == plan.pool.id)
                    }
                    .tag(plan.pool.id)
                    .annotationTitles(selection == plan.pool.id ? .visible : .hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        // Overlay, not safeAreaInset: an inset would push MapKit's logo and legal link up from the bottom edge.
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                // Standard MapKit recenter button, at the bottom (above the pool card when one is selected).
                if model.canRecenterOnUser { // no location, or far from Berlin (e.g. Munich): it would not help
                    MapUserLocationButton(scope: mapScope)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let id = selection, let plan = model.plans.first(where: { $0.pool.id == id }) {
                    Button {
                        model.openPoolID = plan.pool.id // closes the sheet, opens the detail on the list
                    } label: {
                        PoolCard(plan: plan)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: selection)
        // Outside the Berlin area the map must not follow the user (it would show no pools).
        .onAppear { if !model.canRecenterOnUser { position = .region(Self.berlinRegion) } }
        // Standard close button in a toolbar: the OS puts it in the reserved right-hand column on the folded
        // iPhone Duo (like back/star on the detail page). Bar background hidden so the map stays full-bleed.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { FilterMenu() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { model.sheet = nil }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .mapScope(mapScope)
        }
    }
}

/// One marker style for every pool: swimmer symbol, colored by status (grey when closed).
struct PoolPin: View {
    let plan: SwimPlan
    let selected: Bool

    private var active: Bool { plan.status <= .tight }

    var body: some View {
        Image(systemName: "figure.pool.swim")
            .font(.system(size: active ? 13 : 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: active ? 30 : 22, height: active ? 30 : 22)
            .background(plan.status.color.gradient, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 1.5))
            .scaleEffect(selected ? 1.3 : 1)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .frame(width: 44, height: 44) // tap target
            .contentShape(.circle)
            // VoiceOver: "Stadtbad Neukölln, Offen bis 22:00 Uhr" instead of the symbol name
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plan.pool.shortName)
            .accessibilityValue(plan.statusSentence)
            .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview("Karte") {
    PoolMapScreen().environment(AppModel.preview()).preferredColorScheme(.dark)
}
#endif
