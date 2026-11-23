import BadKit
import MapKit
import SwiftUI

struct PoolMapScreen: View {
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.505, longitude: 13.40),
        span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.42)))
    @State private var selection: Int?
    @State private var detail: Pool?

    var body: some View {
        Map(position: $position, selection: $selection) {
            UserAnnotation()
            ForEach(model.plans) { plan in
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

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if plan.status <= .tight {
                    Text("\(plan.usableMinutes)")
                        .font(.caption.weight(.bold)).monospacedDigit()
                } else {
                    Image(systemName: plan.status == .closed ? "xmark" : "figure.pool.swim")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, plan.status <= .tight ? 4 : 0)
            .background(plan.status.color, in: .capsule)
            .overlay(Capsule().stroke(.white, lineWidth: selected ? 3 : 1.5))
            .scaleEffect(selected ? 1.25 : 1)
            .shadow(radius: 3)
        }
        .opacity(plan.status >= .notToday ? 0.7 : 1)
    }
}
