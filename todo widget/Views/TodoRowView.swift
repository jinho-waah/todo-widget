import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct TodoRowView: View {
    @Bindable var todo: Todo
    let isEditMode: Bool
    @Environment(\.modelContext) private var modelContext

    @AppStorage("appLocale") private var appLocale: String = "ko"
    @AppStorage("completionDeleteDelay") private var completionDeleteDelay: Int = 5

    @State private var store = TodoRowStore()

    @FocusState private var subTodoFocused: Bool

    private var sortedSubTodos: [SubTodo] {
        todo.subTodos.sorted { $0.order < $1.order }
    }

    private var isKo: Bool { appLocale.hasPrefix("ko") }
    private var reminderAccentColor: Color {
        RemindersSync.shared.color(forListID: todo.reminderListID) ?? DesignTokens.systemBlue
    }

    private var reminderAccentHeight: CGFloat {
        if let desc = todo.todoDescription, !desc.isEmpty { return 48 }
        return 34
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                CheckboxView(isCompleted: todo.isCompleted, size: DesignTokens.checkbox) {
                    toggleCompletion()
                }
                .padding(.top, 1)
                .disabled(isEditMode)
                .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)

                HStack(alignment: .top, spacing: 8) {
                    reminderAccentBar
                    displayContent
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    if let countdownRemaining = store.state.countdownRemaining {
                        CountdownBadge(
                            seconds: countdownRemaining,
                            total: max(completionDeleteDelay, 1),
                            tint: reminderAccentColor,
                            onCancel: { store.send(.cancelCompletionCountdown(todo: todo)) }
                        )
                        .padding(.trailing, 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    } else {
                        if todo.subTodos.count < 20 {
                            addSubTodoButton
                        }
                        moreButton
                    }
                }
                .disabled(isEditMode)
                .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
                .transition(.opacity)
            }
            .animation(DesignTokens.toggleSpring, value: isEditMode)

            if !todo.subTodos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedSubTodos) { subTodo in
                        SubTodoRowView(subTodo: subTodo, isEditMode: isEditMode)
                            .reorderableRow(
                                item: subTodo,
                                siblings: sortedSubTodos,
                                isEditMode: isEditMode,
                                highlightCornerRadius: 8,
                                highlightInset: -2,
                                // 같은 부모 todo 의 children 끼리만 reorder 허용.
                                canReorder: { $0.parent?.id == subTodo.parent?.id },
                                dragging: draggingSubTodoBinding,
                                dropTargetID: subDropTargetIDBinding
                            ) {
                                Text(subTodo.title)
                                    .font(DesignTokens.subTodoFont)
                                    .foregroundStyle(DesignTokens.textSubTodo)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            // 추가/삭제 대칭 — 양쪽 모두 opacity + scale.
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
                .onDrop(of: [.text], delegate: ReorderDropResetDelegate<SubTodo>(
                    dragging: draggingSubTodoBinding,
                    dropTargetID: subDropTargetIDBinding
                ))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 10, trailing: 6))
        // 빈 제목으로 생성된 새 todo 는 row layoutSpring 등장이 settle 된 뒤 편집 폼을 연다.
        // 0 이면 row 가 그려지기 전에 popover 가 떠 anchor 가 점프하므로
        // DesignTokens.rowAppearSettleDelay 만큼 sleep 한다.
        .task {
            store.send(.autoOpenEditFormIfNeeded(todo))
        }
        .onDisappear {
            store.send(.rowDisappeared)
        }
        // 편집 폼이 닫히면: 제목 비었으면 삭제, 아니면 (date/time 등 모든 변경 포함) push
        .onChange(of: store.state.moreMenu) { previous, current in
            store.send(.moreMenuChanged(
                previous: previous,
                current: current,
                todo: todo,
                context: modelContext
            ))
        }
    }

    // MARK: Bindings

    private var draggingSubTodoBinding: Binding<SubTodo?> {
        Binding(
            get: { store.state.draggingSubTodo },
            set: { store.state.draggingSubTodo = $0 }
        )
    }

    private var subDropTargetIDBinding: Binding<UUID?> {
        Binding(
            get: { store.state.subDropTargetID },
            set: { store.state.subDropTargetID = $0 }
        )
    }

    private var showSubTodoPopoverBinding: Binding<Bool> {
        Binding(
            get: { store.state.showSubTodoPopover },
            set: { store.send(.showSubTodoPopover($0)) }
        )
    }

    private var newSubTodoTitleBinding: Binding<String> {
        Binding(
            get: { store.state.newSubTodoTitle },
            set: { store.send(.updateNewSubTodoTitle($0)) }
        )
    }

    private var moreMenuPresentedBinding: Binding<Bool> {
        Binding(
            get: { store.state.moreMenu != .closed },
            set: { newValue in
                if !newValue { store.send(.closeMoreMenu) }
            }
        )
    }

    // MARK: Completion Countdown

    private func toggleCompletion() {
        store.send(.toggleCompletion(
            todo: todo,
            context: modelContext,
            deleteDelay: completionDeleteDelay
        ))
    }

    // MARK: Display

    private var reminderAccentBar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(reminderAccentColor.opacity(todo.isCompleted ? 0.45 : 0.95))
            .frame(width: 3, height: reminderAccentHeight)
            .padding(.top, 1)
            .animation(DesignTokens.toggleSpring, value: todo.isCompleted)
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(todo.title.isEmpty ? "새 할일" : todo.title)
                .font(DesignTokens.todoTitleFont)
                .foregroundStyle(todo.isCompleted ? DesignTokens.textCompleted : DesignTokens.textPrimary)
                .tracking(-0.1)
                .strikethrough(todo.isCompleted)

            if let desc = todo.todoDescription, !desc.isEmpty {
                Text(desc)
                    .font(DesignTokens.descFont)
                    .foregroundStyle(todo.isCompleted ? DesignTokens.textCompleted : DesignTokens.textSecondary)
                    .strikethrough(todo.isCompleted)
                    .padding(.top, 3)
            }

            dateDisplayRow
        }
    }

    // MARK: Date Display

    private var dateDisplayRow: some View {
        let (text, color, font) = dateDisplayInfo()
        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .regular))
            Text(text)
                .font(font)
                .tracking(-0.05)
        }
        .foregroundStyle(color)
        .padding(.top, 4)
    }

    private func dateDisplayInfo() -> (text: String, color: Color, font: Font) {
        let displayDate = todo.dueDate ?? todo.createdAt

        if todo.isCompleted {
            return (formattedDate(displayDate), DesignTokens.textMetaCompleted, DesignTokens.dateFont)
        }

        guard let due = todo.dueDate else {
            return (formattedDate(displayDate), DesignTokens.textMeta, DesignTokens.dateFont)
        }

        let cal = Calendar.current
        if cal.isDateInToday(due) {
            return (formattedDueDate(due, overdue: false), DesignTokens.systemBlue, DesignTokens.dateFontEmphasized)
        } else if due < cal.startOfDay(for: Date()) {
            return (formattedDueDate(due, overdue: true), DesignTokens.systemRed, DesignTokens.dateFontEmphasized)
        } else {
            return (formattedDueDate(due, overdue: false), DesignTokens.textMeta, DesignTokens.dateFont)
        }
    }

    private func formattedDueDate(_ date: Date, overdue: Bool) -> String {
        let cal = Calendar.current

        var text: String
        if cal.isDateInToday(date) {
            text = isKo ? "오늘" : "Today"
        } else if cal.isDateInTomorrow(date) {
            text = isKo ? "내일" : "Tomorrow"
        } else if cal.isDateInYesterday(date) {
            text = isKo ? "어제" : "Yesterday"
        } else {
            text = formattedDate(date)
        }

        if let time = timeString(date) { text += ", \(time)" }
        if overdue { text += isKo ? " 지남" : " overdue" }
        return text
    }

    private func formattedDate(_ date: Date) -> String {
        let sameYear = Calendar.current.component(.year, from: date)
            == Calendar.current.component(.year, from: Date())
        return DateFormatters.formatter(isKo: isKo, sameYear: sameYear).string(from: date)
    }

    private func timeString(_ date: Date) -> String? {
        let cal = Calendar.current
        guard cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0 else { return nil }
        return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: appLocale)))
    }

    // MARK: Buttons

    private var addSubTodoButton: some View {
        Button {
            store.send(.showSubTodoPopover(true))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.dotColor)
                .frame(width: DesignTokens.menuButton, height: DesignTokens.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: showSubTodoPopoverBinding, arrowEdge: .trailing) {
            subTodoPopover
        }
    }

    private var moreButton: some View {
        Button {
            // popover 열 시점에 list snapshot 을 캐싱 → 매 render 마다 EventStore 호출 회피.
            store.send(.openActions)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.dotColor)
                .frame(width: DesignTokens.menuButton, height: DesignTokens.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            // 단일 popover — 액션 / 편집 폼 컨텐츠를 swap.
            // 두 개의 .popover 를 같은 anchor 에 붙이면 macOS 에서 둘 중 하나만 동작하는 케이스가 있어 통합.
            isPresented: moreMenuPresentedBinding,
            arrowEdge: .trailing
        ) {
            moreMenuContent
        }
    }

    @ViewBuilder
    private var moreMenuContent: some View {
        switch store.state.moreMenu {
        case .actions:
            TodoActionsPopover(
                lists: store.state.availableLists,
                currentListID: todo.reminderListID ?? RemindersSync.shared.defaultListID,
                onEdit: { store.send(.showEditForm) },
                onSelectList: { listID in
                    store.send(.selectList(todo: todo, listID: listID))
                },
                onCreateList: {
                    store.send(.showCreateList)
                },
                onDelete: {
                    store.send(.deleteTodo(todo: todo, context: modelContext))
                }
            )
        case .editForm:
            EditTodoFormView(todo: todo)
        case .createList:
            CreateReminderListPopover(
                onCancel: { store.send(.openActions) },
                onCreate: createReminderListForExistingTodo
            )
        case .closed:
            EmptyView()
        }
    }

    private func createReminderListForExistingTodo(_ title: String, color: NSColor) {
        store.send(.createReminderList(todo: todo, title: title, color: color))
    }

    // MARK: Sub-todo Popover

    private var subTodoPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(title: "세부 할일", onClose: nil)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: newSubTodoTitleBinding)
                .textFieldStyle(.plain)
                .font(DesignTokens.subTodoFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($subTodoFocused)
                .onSubmit { submitSubTodo() }

            Divider().padding(.horizontal, 8)

            HStack {
                Button("취소") {
                    store.send(.cancelSubTodo)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button("추가") { submitSubTodo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.state.newSubTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { subTodoFocused = true }
    }

    private func submitSubTodo() {
        store.send(.submitSubTodo(todo: todo, context: modelContext))
    }
}
