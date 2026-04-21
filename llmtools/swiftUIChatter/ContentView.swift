import SwiftUI

struct SubmitButton: View {
    @Environment(ChattViewModel.self) private var vm
    @State private var isSending = false

    var body: some View {
        Button {
            isSending = true
            Task(priority: .background) {
                if let appID = vm.appID {
                    await ChattStore.shared.llmTools(
                        appID: appID,
                        chatt: Chatt(name: vm.onTrailingEnd, message: vm.message),
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

struct ChattView: View {
    let chatt: Chatt
    @Environment(ChattViewModel.self) private var vm

    var body: some View {
        HStack {
            if chatt.name == vm.onTrailingEnd {
                Spacer()
            }
            Text(chatt.message ?? "")
                .padding(10)
                .background(chatt.name == vm.onTrailingEnd ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(chatt.name == vm.onTrailingEnd ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(chatt.name == vm.onTrailingEnd ? .leading : .trailing, 40)
            if chatt.name != vm.onTrailingEnd {
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}

struct ContentView: View {
    @Environment(ChattViewModel.self) private var vm
    @FocusState private var messageInFocus: Bool

    var body: some View {
        VStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack {
                        ForEach(ChattStore.shared.chatts) { chatt in
                            ChattView(chatt: chatt)
                                .id(chatt.id)
                        }
                    }
                }
                .onChange(of: ChattStore.shared.chatts.count) {
                    scrollProxy.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
                }

                HStack(alignment: .bottom) {
                    TextField(vm.instruction, text: Bindable(vm).message)
                        .focused($messageInFocus)
                        .textFieldStyle(.roundedBorder)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                        .background(Color(.clear))
                        .border(Color(.clear))
                    SubmitButton()
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 0))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            messageInFocus.toggle()
        }
        .navigationTitle("llmTools")
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
