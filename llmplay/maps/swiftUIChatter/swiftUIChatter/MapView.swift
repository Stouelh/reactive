import MapKit
import SwiftUI

struct MapView: View {
    @Environment(ChattViewModel.self) private var vm
    @State private var selection: Chatt?
    
    var body: some View {
        Map(position: Bindable(vm).cameraPosition, selection: $selection) {
            if let chatt = vm.selected {
                if let geodata = chatt.geodata {
                    Marker(chatt.name!, systemImage: "figure.wave",
                           coordinate: CLLocationCoordinate2D(latitude: geodata.lat, longitude: geodata.lon))
                    .tint(.red)
                    .tag(chatt)
                }
            } else {
                ForEach(ChattStore.shared.chatts, id: \.self) { chatt in
                    if let geodata = chatt.geodata {
                        Marker(chatt.name!, systemImage: "figure.wave",
                               coordinate: CLLocationCoordinate2D(latitude: geodata.lat, longitude: geodata.lon))
                        .tint(.mint)
                    }
                }
            }
            if let chatt = selection, let geodata = chatt.geodata {
                Annotation(chatt.name!, coordinate: CLLocationCoordinate2D(latitude: geodata.lat, longitude: geodata.lon), anchor: .topLeading) {
                    InfoView(chatt: chatt)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
}

struct InfoView: View {
    let chatt: Chatt
    @State private var postedFrom: AttributedString = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let username = chatt.name, let timestamp = chatt.timestamp {
                    Text(username).padding(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 0)).font(.system(size: 16))
                    Spacer()
                    Text(timestamp).padding(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 4)).font(.system(size: 12))
                }
            }
            if let message = chatt.message {
                Text(message).padding(EdgeInsets(top: 1, leading: 8, bottom: 0, trailing: 4)).font(.system(size: 14)).lineLimit(2, reservesSpace: true)
            }
            if let geodata = chatt.geodata {
                Text(postedFrom)
                    .task { postedFrom = await geodata.postedFrom }
                    .padding(EdgeInsets(top: 0, leading: 8, bottom: 10, trailing: 4)).font(.system(size: 12)).lineLimit(2, reservesSpace: true)
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .cornerRadius(4.0)
        }
        .frame(width: 300)
    }
}
