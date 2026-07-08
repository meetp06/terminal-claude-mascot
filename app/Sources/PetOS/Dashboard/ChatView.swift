// Talk to the Manager agent. In phase 1 the manager can plan and explain but
// will refuse to actually change or run anything.
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Group {
                    if model.messages.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "Manager is ready",
                            subtitle: "Ask for a plan, a review, or a read-only investigation.")
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.messages) { msg in
                                    bubble(msg)
                                        .id(msg.id)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .onChange(of: model.messages.count) { _ in
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack(spacing: 10) {
                TextField("Ask the manager to look into something...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .help("Send")
            }
            .padding(12)
            .petPanel(padding: 0, raised: true)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.chat(text)
        draft = ""
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.sender == "user"
        return HStack {
            if isUser { Spacer() }
            Text(msg.text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isUser ? Brand.teal.opacity(0.92) : Color.white.opacity(0.075),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isUser ? Color.clear : Brand.hairline, lineWidth: 1)
                )
                .foregroundStyle(isUser ? Color.black.opacity(0.86) : Brand.strongText)
                .frame(maxWidth: 460, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer() }
        }
    }
}
