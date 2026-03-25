import SwiftUI

struct ContentView: View {
    @Environment(ChattViewModel.self) private var vm
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Timeline
            ScrollViewReader { proxy in
                ChattScrollView { selected in
                    Task(priority: .background) {
                        await startReplyDraft(from: selected)
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }

            Divider()

            // Input area
            HStack(spacing: 10) {
                // AI button (sparkles)
                Button {
                    Task(priority: .background) {
                        await startRewrite()
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(aiButtonEnabled ? .blue : .gray)
                }
                .disabled(!aiButtonEnabled)

                // Multi-line text field
                TextField(
                    vm.llmInProgress ? "Thinking..." : vm.instruction,
                    text: Bindable(vm).message,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.llmInProgress)

                // Submit button (send)
                Button {
                    Task(priority: .background) {
                        await submitPost()
                    }
                } label: {
                    if vm.llmInProgress {
                        // Show loading during LLM request
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(sendButtonEnabled ? .blue : .gray)
                    }
                }
                .disabled(!sendButtonEnabled)
            }
            .padding()
        }
        .navigationTitle("Chatter")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshTimeline()
        }
        .alert("Error", isPresented: Bindable(vm).showError) {
            Button("OK", role: .cancel) {
                vm.errMsg = ""
            }
        } message: {
            Text(vm.errMsg)
        }
    }

    // MARK: - Button States
    
    private var aiButtonEnabled: Bool {
        !vm.llmInProgress && !vm.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonEnabled: Bool {
        !vm.llmInProgress && !vm.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Timeline Management

    private func refreshTimeline() async {
        await ChattStore.shared.getChatts(errMsg: Bindable(vm).errMsg)
        if !vm.errMsg.isEmpty {
            vm.showError = true
        }
        
        // Scroll to bottom
        await MainActor.run {
            withAnimation {
                scrollProxy?.scrollTo(ChattStore.shared.chatts.last?.id, anchor: .bottom)
            }
        }
    }

    private func submitPost() async {
        let text = vm.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let chatt = Chatt(name: vm.onTrailingEnd, message: text)
        vm.message = ""

        await ChattStore.shared.postChatt(chatt, errMsg: Bindable(vm).errMsg)
        
        if !vm.errMsg.isEmpty {
            vm.showError = true
        } else {
            //Refresh timeline after posting
            await refreshTimeline()
        }
    }

    // MARK: - LLM Draft Functions (Project 1)

    private func startRewrite() async {
        guard !vm.llmInProgress else { return }

        vm.llmInProgress = true
        defer { vm.llmInProgress = false }

        let rewritePrompt = """
        You are a poet. Rewrite the content below to a poetic version. Don't list options. Here's the content I want you to rewrite:
        """
        
        await promptLlm(prompt: rewritePrompt, sourceText: vm.message)
    }

    private func startReplyDraft(from selected: Chatt) async {
        guard !vm.llmInProgress else { return }

        vm.llmInProgress = true
        defer { vm.llmInProgress = false }

        let replyPrompt = """
        You are a poet. Write a poetic reply to this message I received. Don't list options. Here's the message I want you to write a poetic reply to:
        """
        
        await promptLlm(prompt: replyPrompt, sourceText: selected.message ?? "")
    }

    private func promptLlm(prompt: String, sourceText: String) async {
        vm.draft = ""
        vm.errMsg = ""
        
        let model = "gemma3:270m"
        let fullPrompt = prompt + "\n\n" + sourceText

        let chatt = Chatt(name: model, message: fullPrompt)

        // Clear message box to show draft as it streams
        vm.message = ""

        await ChattStore.shared.llmDraft(
            chatt,
            draft: Bindable(vm).draft,
            errMsg: Bindable(vm).errMsg
        )

        // Put final draft in message box
        if vm.errMsg.isEmpty {
            vm.message = vm.draft
        } else {
            vm.showError = true
        }
    }
}
