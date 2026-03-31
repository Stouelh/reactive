import SwiftUI
import MapKit

struct SubmitButton: View {
    @Binding var cameraPosition: MapCameraPosition
    @Environment(ChattViewModel.self) private var vm
    @State private var isSending = false

    var body: some View {
        Button {
            isSending = true
            Task(priority: .background) {
                if let appID = vm.appID {
                    await ChattStore.shared.llmPlay(
                        appID: appID,
                        chatt: Chatt(name: vm.onTrailingEnd, message: vm.message),
                        hints: Bindable(vm).hints,
                        winner: { loc in
                            print("lat: \(loc.lat), lon: \(loc.lon)")
                            cameraPosition = .camera(MapCamera(
                                centerCoordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lon),
                                distance: 14000, heading: 0, pitch: 60))
                        },
                        errMsg: Bindable(vm).errMsg)
                }
                vm.message = ""
                isSending = false
                vm.showError = !vm.errMsg.isEmpty
            }
        } label: {
            if isSending {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    .padding(10)
            } else {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(vm.message.isEmpty ? .gray : .yellow)
                    .padding(10)
            }
        }
        .disabled(isSending || vm.message.isEmpty)
        .background(Color(isSending || vm.message.isEmpty ? .secondarySystemBackground : .systemBlue))
        .clipShape(Circle())
        .padding(.trailing)
    }
}

struct ContentView: View {
    @Environment(ChattViewModel.self) private var vm
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var messageInFocus: Bool

    var body: some View {
        VStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            
            VStack {
                Text(vm.hints.isEmpty ? "Waiting for hints..." : vm.hints)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(alignment: .bottom) {
                    TextField(vm.instruction, text: Bindable(vm).message)
                        .focused($messageInFocus)
                        .textFieldStyle(.roundedBorder)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                        .background(Color(.clear))
                        .border(Color(.clear))
                    SubmitButton(cameraPosition: $cameraPosition)
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 0))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            messageInFocus.toggle()
        }
        .navigationTitle("Where in the world?")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Bindable(vm).showError) {
            Button("OK") {
                vm.errMsg = ""
            }
        } message: {
            Text(vm.errMsg)
        }
    }
}
