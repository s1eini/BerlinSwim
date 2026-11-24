import BadKit
import MapKit
import SwiftUI

struct PoolMapScreen: View {
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.505, longitude: 13.40),
        span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.42))))
    @State private var selection: Int?

    var body: some View {
        NavigationStack {
        Map(position: $position, selection: $selection) {
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
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            FilterBar().padding(.horizontal, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if let id = selection, let plan = model.plans.first(where: { $0.pool.id == id }) {
                NavigationLink(value: plan.pool) {
                    PoolCard(plan: plan)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selection)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Pool.self) { pool in
            PoolPager(plans: [model.plan(for: pool)], selected: pool)
        }
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
