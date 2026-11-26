import SwiftUI

/// Inline Wi-Fi password row: lock icon, field with show/hide eye, and a Join button.
struct PasswordEntry: View {
    @Binding var text: String
    var failed = false
    var onSubmit: () -> Void

    @State private var reveal = false
    @FocusState private var focused: Bool

    private var ring: Color { failed ? Theme.bad : focused ? Theme.accent : Color.primary.opacity(0.12) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                    .foregroundStyle(focused ? Theme.accent : Color.secondary)
                field
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focused).onSubmit(submit)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button { text = ""; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.7))
                    }.buttonStyle(.plain).help("Clear")
                }
                Button { reveal.toggle(); focused = true } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").font(.system(size: 12))
                        .foregroundStyle(reveal ? Theme.accent : Color.secondary).frame(width: 18)
                }.buttonStyle(.plain).help(reveal ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ring, lineWidth: focused || failed ? 1.5 : 1))
            .animation(.easeOut(duration: 0.12), value: focused)

            Button("Join", action: submit)
                .buttonStyle(Pill(fill: Theme.accent, fg: .black))
                .disabled(text.isEmpty).opacity(text.isEmpty ? 0.45 : 1)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    @ViewBuilder private var field: some View {
        if reveal { TextField("Password", text: $text) } else { SecureField("Password", text: $text) }
    }

    private func submit() { if !text.isEmpty { onSubmit() } }
}
