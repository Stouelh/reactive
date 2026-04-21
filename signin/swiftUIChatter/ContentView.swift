import SwiftUI

struct SubmitButton: View {
    @Binding var scrollProxy: ScrollViewProxy?
    var focus: FocusState<Bool>.Binding
    @Environment(ChattViewModel.self) private var vm
    @State private var isSending = false

    var body: some View {
        Button {
            isSending = true
            Task(priority: .background) {
                if (ChatterID.shared.id == nil) {
                    await withUnsafeContinuation { submitAt in
                        vm.signinCompletion = { () -> Void in
                            vm.onTrailingEnd = ChatterID.shared.creator
                            submitAt.resume()
                        }
                        vm.getSignedin = true
                    }
                    // here be submitAt
                }

                // may still be nil if signin failed
                if (ChatterID.shared.id != nil) {
                    await ChattStore.shared.postChatt(Chatt(name: vm.onTrailingEnd, message: vm.message), errMsg: Bindable(vm).errMsg)
                    if vm.showOk || vm.errMsg.isEmpty {
                        await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
                        Task(priority: .userInitiated) {
                            withAnimation {
                                scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                                focus.wrappedValue = false
                            }
                        }
                        // else delete chatterID
                    } else if vm.errMsg.contains("401") {
                        // delete potentially invalid chatterID from Keychain
                        await ChatterID.shared.delete(Bindable(vm).errMsg)
                    }
                }
                vm.message = ""
                isSending = false
                vm.showError = !vm.showOk && !vm.errMsg.isEmpty
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
    @FocusState private var messageInFocus: Bool
    @State private var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        ForEach(ChattStore.shared.chatts) { chatt in
                            HStack {
                                if chatt.name == vm.onTrailingEnd { Spacer() }
                                Text(chatt.message ?? "")
                                    .padding(10)
                                    .background(chatt.name == vm.onTrailingEnd ? Color.blue : Color(.secondarySystemBackground))
                                    .foregroundColor(chatt.name == vm.onTrailingEnd ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(chatt.name == vm.onTrailingEnd ? .leading : .trailing, 40)
                                if chatt.name != vm.onTrailingEnd { Spacer() }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                            .id(chatt.id)
                        }
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    Task {
                        await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
                        scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                    }
                }

                HStack(alignment: .bottom) {
                    TextField(vm.instruction, text: Bindable(vm).message)
                        .focused($messageInFocus)
                        .textFieldStyle(.roundedBorder)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                        .background(Color(.clear))
                        .border(Color(.clear))
                    SubmitButton(scrollProxy: $scrollProxy, focus: $messageInFocus)
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 0))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            messageInFocus.toggle()
        }
        .navigationTitle("Chatter")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Bindable(vm).showError) {
            Button("OK") {
                vm.errMsg = ""
            }
        } message: {
            Text(vm.errMsg)
        }
        .alert("Advisory", isPresented: Bindable(vm).showOk) {
            Button("OK") {
                vm.errMsg = ""
            }
        } message: {
            Text(vm.errMsg)
        }
        .sheet(isPresented: Bindable(vm).getSignedin) {
            SigninView(isPresenting: Bindable(vm).getSignedin)
                .presentationDetents([.fraction(0.25)])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
    }
}
