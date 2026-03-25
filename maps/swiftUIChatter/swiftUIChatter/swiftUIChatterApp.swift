import SwiftUI
import MapKit

@Observable
final class ChattViewModel {
    let onTrailingEnd = "stouelh"
    let instruction = "Type a message…"
    var message = ""
    var errMsg = ""
    var showError = false
    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var selected: Chatt? = nil
    var showMap = false
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()
    
    init() {
        LocManager.shared.startUpdates()
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .onAppear {
                        let scenes = UIApplication.shared.connectedScenes
                        let windowScene = scenes.first as? UIWindowScene
                        if let wnd = windowScene?.windows.first {
                            let lagFreeField = UITextField()
                            wnd.addSubview(lagFreeField)
                            lagFreeField.becomeFirstResponder()
                            lagFreeField.resignFirstResponder()
                            lagFreeField.removeFromSuperview()
                        }
                    }
            }
            .environment(viewModel)
        }
    }
}
