import SwiftUI
import MapKit

struct SubmitButton: View {
    @Binding var scrollProxy: ScrollViewProxy?
    @Environment(ChattViewModel.self) private var vm
    @State private var isSending = false
    
    var body: some View {
        Button {
            isSending = true
            Task(priority: .background) {
                let geodata = GeoData(
                    lat: LocManagerViewModel.shared.location.lat,
                    lon: LocManagerViewModel.shared.location.lon,
                    facing: LocManagerViewModel.shared.compassHeading,
                    speed: LocManagerViewModel.shared.speed)
                await ChattStore.shared.postChatt(
                    Chatt(name: vm.onTrailingEnd, message: vm.message, geodata: geodata),
                    errMsg: Bindable(vm).errMsg)
                if vm.errMsg.isEmpty {
                    await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
                }
                vm.message = ""
                isSending = false
                vm.showError = !vm.errMsg.isEmpty
                Task(priority: .userInitiated) {
                    withAnimation {
                        scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                    }
                }
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
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var messageInFocus: Bool
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ChattScrollView()
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .refreshable {
                        await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
                        Task(priority: .userInitiated) {
                            withAnimation {
                                scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                            }
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                        .onEnded { value in
                            if case (...0, -100...100) = (value.translation.width, value.translation.height) {
                                vm.selected = nil
                                vm.cameraPosition = .camera(MapCamera(
                                    centerCoordinate: CLLocationCoordinate2D(
                                        latitude: LocManagerViewModel.shared.location.lat,
                                        longitude: LocManagerViewModel.shared.location.lon),
                                    distance: 500, heading: 0, pitch: 0))
                                vm.showMap.toggle()
                            }
                        }
                    )
            }
            HStack(alignment: .top) {
                VStack(alignment: .trailing) {
                    TextField(vm.instruction, text: Bindable(vm).message)
                        .focused($messageInFocus)
                        .textFieldStyle(.roundedBorder)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                        .background(Color(.clear))
                        .border(Color(.clear))
                        .padding(.leading, 20)
                    Text("lat/lon: \(LocManagerViewModel.shared.location.lat)/\(LocManagerViewModel.shared.location.lon)")
                        .font(.caption)
                        .foregroundColor(Color(.systemGray3))
                        .padding(.trailing, 20)
                }
                SubmitButton(scrollProxy: $scrollProxy)
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
        }
        .contentShape(.rect)
        .onTapGesture {
            messageInFocus.toggle()
        }
        .task(priority: .background) {
            await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
            vm.showError = !vm.errMsg.isEmpty
            Task(priority: .userInitiated) {
                withAnimation {
                    scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                }
            }
        }
        .navigationDestination(isPresented: Bindable(vm).showMap) {
            MapView()
        }
        .navigationTitle("Chatter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "map")
                    .foregroundStyle(.blue)
                    .onTapGesture {
                        vm.selected = nil
                        vm.cameraPosition = .camera(MapCamera(
                            centerCoordinate: CLLocationCoordinate2D(
                                latitude: LocManagerViewModel.shared.location.lat,
                                longitude: LocManagerViewModel.shared.location.lon),
                            distance: 500, heading: 0, pitch: 0))
                        vm.showMap.toggle()
                    }
            }
        }
        .alert("Error", isPresented: Bindable(vm).showError) {
            Button("OK") {
                vm.errMsg = ""
            }
        } message: {
            Text(vm.errMsg)
        }
    }
}
