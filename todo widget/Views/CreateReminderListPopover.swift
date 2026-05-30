import SwiftUI
import AppKit

struct ReminderListSwatch: Identifiable, Equatable {
    let id: String
    let color: Color
    let nsColor: NSColor

    static func == (lhs: ReminderListSwatch, rhs: ReminderListSwatch) -> Bool {
        lhs.id == rhs.id
    }
}

private let reminderListSwatches: [ReminderListSwatch] = [
    ReminderListSwatch(id: "blue", color: .blue, nsColor: .systemBlue),
    ReminderListSwatch(id: "green", color: .green, nsColor: .systemGreen),
    ReminderListSwatch(id: "yellow", color: .yellow, nsColor: .systemYellow),
    ReminderListSwatch(id: "orange", color: .orange, nsColor: .systemOrange),
    ReminderListSwatch(id: "red", color: .red, nsColor: .systemRed),
    ReminderListSwatch(id: "pink", color: .pink, nsColor: .systemPink),
    ReminderListSwatch(id: "purple", color: .purple, nsColor: .systemPurple),
    ReminderListSwatch(id: "gray", color: .gray, nsColor: .systemGray)
]

struct CreateReminderListPopover: View {
    let onCancel: () -> Void
    let onCreate: (String, NSColor) -> Void

    @State private var title = ""
    @State private var selectedSwatch = reminderListSwatches[0]
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(title: "새 목록", onClose: nil)

            Divider().padding(.horizontal, 8)

            TextField("목록 이름", text: $title)
                .textFieldStyle(.plain)
                .font(DesignTokens.todoTitleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($titleFocused)
                .onSubmit { submit() }

            Divider().padding(.horizontal, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                ForEach(reminderListSwatches) { swatch in
                    Button {
                        selectedSwatch = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if selectedSwatch == swatch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(
                                Circle()
                                    .strokeBorder(DesignTokens.buttonStroke, lineWidth: 0.5)
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소", action: onCancel)
                    .buttonStyle(.glass)
                Spacer()
                Button("생성") { submit() }
                    .buttonStyle(.glassProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { titleFocused = true }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, selectedSwatch.nsColor)
    }
}
