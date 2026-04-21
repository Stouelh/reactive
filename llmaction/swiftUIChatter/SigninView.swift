import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

extension GIDSignIn {
    func signInAsync(withPresenting presenting: UIViewController) async -> String? {
        return await withUnsafeContinuation { cont in
            signIn(withPresenting: presenting) { result, error in
                if let result, let token = result.user.idToken?.tokenString {
                    cont.resume(returning: token)
                } else {
                    print("Google SignIn error: \(String(describing: error?.localizedDescription))")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    func restorePreviousSignInAsync() async -> String? {
        return await withUnsafeContinuation { cont in
            restorePreviousSignIn() { user, error in
                if let token = user?.idToken?.tokenString {
                    cont.resume(returning: token)
                } else {
                    print("Google Restore SignIn error: \(String(describing: error?.localizedDescription))")
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

struct SigninView: View {
    @Environment(ChattViewModel.self) private var vm
    @Binding var isPresenting: Bool
    private let signinClient = GIDSignIn.sharedInstance

    var body: some View {
        if let rootVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.rootViewController {
            VStack {
                Spacer()
                Text("Click once. Signing in with UIKit. Be patient.")
                Spacer()
                GoogleSignInButton {
                    Task {
                        if let token = await signinClient.signInAsync(withPresenting: rootVC) {
                            getChatterID(token)
                        } else {
                            vm.errMsg = "Failed Google Sign-In. Please try again."
                        }
                        isPresenting.toggle()
                    }
                }
                .frame(width: 100, height: 50, alignment: Alignment.center)
                .task {
                    if let token = signinClient.currentUser?.idToken?.tokenString {
                        getChatterID(token)
                        isPresenting.toggle()
                    } else if let token = await signinClient.restorePreviousSignInAsync() {
                        getChatterID(token)
                        isPresenting.toggle()
                    } // else show GoogleSignInButton and let user sign in
                }
                Spacer()
            }
        }
    }

    private func getChatterID(_ token: String) {
        Task(priority: .background) {
            if let _ = await ChattStore.shared.addUser(token, errMsg: Bindable(vm).errMsg) {
                await ChatterID.shared.save(errMsg: Bindable(vm).errMsg, showOk: Bindable(vm).showOk)
                if vm.errMsg.isEmpty {
                    vm.showOk = true
                    vm.errMsg = "ChatterID refreshed."
                }
                await vm.signinCompletion?()
            }
        }
    }
}
