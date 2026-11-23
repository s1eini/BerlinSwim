import BadKit
import MapKit
import SwiftUI

struct PoolMapScreen: View {
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.505, longitude: 13.40),
        span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.42))))
    @State private var selection: Int?
    @State private var detail: Pool?

    var body: some View {
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
                Button { detail = plan.pool } label: {
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
        .sheet(item: $detail) { pool in
            NavigationStack { PoolDetailView(pool: pool) }
                .presentationDetents([.medium, .large])
        }
    }
}

struct PoolPin: View {
    let plan: SwimPlan
    let selected: Bool

    private var active: Bool { plan.status <= .tight }

    var body: some View {
        if active {
            Group {
                if let lane = plan.window?.laneLength ?? plan.pool.laneLength {
                    Text("\(lane)").font(.caption.weight(.heavy)).monospacedDigit()
                } else {
                    Image(systemName: "figure.pool.swim").font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(plan.status.color.gradient, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
            .overlay(alignment: .topTrailing) {
                if !plan.pool.warnings.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2).foregroundStyle(.black, .yellow)
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(selected ? 1.3 : 1)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.85))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                .scaleEffect(selected ? 1.6 : 1)
        }
    }
}
