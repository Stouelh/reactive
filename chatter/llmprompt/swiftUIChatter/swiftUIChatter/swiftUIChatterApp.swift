import SwiftUI

@Observable
final class ChattViewModel {
    let onTrailingEnd = "gemma3:270m"
    let instruction = "Type a message…"
    var message = "howdy?"
    
    var errMsg = ""
    var showError = false
}

@main
struct swiftUIChatterApp: App {
    let viewModel = ChattViewModel()
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
