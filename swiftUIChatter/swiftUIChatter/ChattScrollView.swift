import SwiftUI

struct ChattView: View {
    @Environment(ChattViewModel.self) private var vm
    
    let chatt: Chatt
    let onTrailingEnd: Bool
    let onReplyRequest: (Chatt) -> Void
    
    var body: some View {
        VStack(alignment: onTrailingEnd ? .trailing : .leading, spacing: 4) {
            if let msg = chatt.message, !msg.isEmpty {
                
                // Name (only for non-user chatts)
                Text(onTrailingEnd ? "" : chatt.name)
                    .font(.subheadline)
                    .foregroundColor(.purple)
                    .padding(.leading, 4)
                
                // Message bubble
                Text(msg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color(onTrailingEnd ? .systemBlue :
                              (vm.selectedChattId == chatt.id ? .systemGray5 : .systemBackground))
                    )
                    .foregroundColor(onTrailingEnd ? .white : .primary)
                    .cornerRadius(20)
                    .shadow(radius: 2)
                    .frame(maxWidth: 300, alignment: onTrailingEnd ? .trailing : .leading)
                    // Long-press only if not own chatt + no LLM in progress
                    .onLongPressGesture {
                        if !onTrailingEnd && !vm.llmInProgress {
                            vm.selectedChattId = chatt.id
                            onReplyRequest(chatt)
                        }
                    }
                
                // Timestamp
                Text(chatt.timestamp)
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct ChattScrollView: View {
    @Environment(ChattViewModel.self) private var vm
    let onReplyRequest: (Chatt) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(ChattStore.shared.chatts) { chatt in
                    ChattView(
                        chatt: chatt,
                        onTrailingEnd: chatt.name == vm.onTrailingEnd,
                        onReplyRequest: onReplyRequest
                    )
                }
            }
        }
    }
}
