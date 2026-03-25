import SwiftUI

struct SubmitButton: View {
    @Binding var scrollProxy: ScrollViewProxy?
    @Environment(ChattViewModel.self) private var vm
    @State private var isSending = false
    
    var body: some View {
        Button {
            isSending = true
            Task(priority: .background) {
                await ChattStore.shared.postChatt(
                    Chatt(name: vm.onTrailingEnd, message: vm.message),
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
            }
            HStack(alignment: .bottom) {
                TextField(vm.instruction, text: Bindable(vm).message)
                    .focused($messageInFocus)
                    .textFieldStyle(.roundedBorder)
                    .cornerRadius(20)
                    .shadow(radius: 2)
                    .background(Color(.clear))
                    .border(Color(.clear))
                SubmitButton(scrollProxy: $scrollProxy)
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 0))
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
        .navigationTitle("Chatter")
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
