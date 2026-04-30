import SwiftUI
import SwiftData

// Todo 의 제목/설명/날짜·시간 편집 popover.
// 새 todo (빈 제목으로 생성된 placeholder) 면 헤더 라벨이 "새 할일", 저장 버튼이 "추가".

struct EditTodoFormView: View {
    @Bindable var todo: Todo
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var desc: String
    @FocusState private var titleFocused: Bool
    private let isNew: Bool

    init(todo: Todo) {
        self.todo = todo
        let empty = todo.title.isEmpty
        _title = State(initialValue: todo.title)
        _desc = State(initialValue: todo.todoDescription ?? "")
        self.isNew = empty
    }

    private var hasTime: Bool {
        guard let d = todo.dueDate else { return false }
        let c = Calendar.current
        return c.component(.hour, from: d) != 0 || c.component(.minute, from: d) != 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "새 할일" : "수정")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMeta)
                    .tracking(0.3)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: $title)
                .textFieldStyle(.plain)
                .font(DesignTokens.todoTitleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($titleFocused)
                .onSubmit { save() }

            Divider().padding(.horizontal, 8)

            TextField("설명 추가", text: $desc, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(DesignTokens.descFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            Divider().padding(.horizontal, 8)

            dateRow

            if todo.dueDate != nil {
                Divider().padding(.horizontal, 8)
                timeRow
            }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button(isNew ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 260)
        .onAppear { titleFocused = true }
    }

    // MARK: Date / Time Rows

    private var dateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 14)

            if todo.dueDate != nil {
                DatePicker(
                    "",
                    selection: Binding(get: { todo.dueDate ?? Date() }, set: { todo.dueDate = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button {
                    todo.dueDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            } else {
                Text("날짜 추가")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if todo.dueDate == nil {
                todo.dueDate = Calendar.current.startOfDay(for: Date())
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 14)

            if hasTime {
                DatePicker(
                    "",
                    selection: Binding(get: { todo.dueDate ?? Date() }, set: { todo.dueDate = $0 }),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button {
                    if let d = todo.dueDate {
                        todo.dueDate = Calendar.current.startOfDay(for: d)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            } else {
                Text("시간 추가")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if !hasTime, let d = todo.dueDate {
                let now = Date()
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day], from: d)
                comps.hour = cal.component(.hour, from: now)
                comps.minute = cal.component(.minute, from: now)
                todo.dueDate = cal.date(from: comps)
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        todo.title = t
        let d = desc.trimmingCharacters(in: .whitespaces)
        todo.todoDescription = d.isEmpty ? nil : d
        Task { await RemindersSync.shared.push(todo) }
        dismiss()
    }
}
