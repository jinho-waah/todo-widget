import SwiftUI
import SwiftData
import AppKit

// Todo 의 제목/설명/날짜·시간 편집 popover.
// 새 todo (빈 제목으로 생성된 placeholder) 면 헤더 라벨이 "새 할일", 저장 버튼이 "추가".

struct EditTodoFormView: View {
    @Bindable var todo: Todo
    @Environment(\.dismiss) private var dismiss

    @State private var store: EditTodoFormStore
    @FocusState private var titleFocused: Bool

    init(todo: Todo) {
        self.todo = todo
        _store = State(initialValue: EditTodoFormStore(todo: todo))
    }

    private var hasTime: Bool {
        store.hasTime(todo)
    }

    private var currentListID: String? {
        todo.reminderListID ?? RemindersSync.shared.defaultListID
    }

    private var currentList: ReminderList? {
        store.state.availableLists.first { $0.id == currentListID }
    }

    var body: some View {
        if store.state.showCreateListForm {
            CreateReminderListPopover(
                onCancel: { store.send(.showCreateListForm(false)) },
                onCreate: createReminderListForNewTodo
            )
        } else {
            formContent
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // macOS popover 는 바깥 클릭으로 자연스럽게 dismiss 되므로 X 버튼은 숨긴다.
            PopoverHeader(title: store.isNew ? "새 할일" : "수정", onClose: nil)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: titleBinding)
                .textFieldStyle(.plain)
                .font(DesignTokens.todoTitleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($titleFocused)
                .onSubmit { save() }

            Divider().padding(.horizontal, 8)

            TextField("설명 추가", text: descriptionBinding, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(DesignTokens.descFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            if store.isNew, !store.state.availableLists.isEmpty {
                Divider().padding(.horizontal, 8)
                listRow
            }

            Divider().padding(.horizontal, 8)

            dateRow

            if todo.dueDate != nil {
                Divider().padding(.horizontal, 8)
                timeRow
            }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소") { store.send(.dismiss(dismiss)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button(store.isNew ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.state.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 260)
        .onAppear {
            store.send(.appeared)
            titleFocused = true
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.state.title },
            set: { store.send(.updateTitle($0)) }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { store.state.desc },
            set: { store.send(.updateDescription($0)) }
        )
    }

    // MARK: List / Date / Time Rows

    private var listRow: some View {
        Menu {
            ForEach(store.state.availableLists) { list in
                Button {
                    store.send(.selectList(todo: todo, list.id))
                } label: {
                    if list.id == currentListID {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
            Divider()
            Button {
                store.send(.showCreateListForm(true))
            } label: {
                Label("새 목록 생성", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 14)

                Circle()
                    .fill(currentList?.color ?? DesignTokens.systemBlue)
                    .frame(width: 9, height: 9)

                Text(currentList?.title ?? "기본 목록")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMeta)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func createReminderListForNewTodo(_ listTitle: String, color: NSColor) {
        store.send(.createReminderList(todo: todo, title: listTitle, color: color))
    }

    private var dateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 14)

            if todo.dueDate != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { todo.dueDate ?? Date() },
                        set: { store.send(.setDueDate(todo: todo, $0)) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                // ja_JP locale 의 short date format 이 yyyy/MM/dd 라
                // 시스템 locale 과 무관하게 슬래시 포맷을 강제한다.
                .environment(\.locale, Locale(identifier: "ja_JP"))

                Spacer()

                Button {
                    store.send(.setDueDate(todo: todo, nil))
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
            store.send(.addDateIfNeeded(todo: todo))
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
                    selection: Binding(
                        get: { todo.dueDate ?? Date() },
                        set: { store.send(.setDueDate(todo: todo, $0)) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button {
                    store.send(.clearTime(todo: todo))
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
            store.send(.addTimeIfNeeded(todo: todo))
        }
    }

    private func save() {
        store.send(.save(todo: todo, dismiss: dismiss))
    }
}
