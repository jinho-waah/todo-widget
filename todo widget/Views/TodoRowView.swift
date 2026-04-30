import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TodoRowView: View {
    @Bindable var todo: Todo
    let isEditMode: Bool
    @Environment(\.modelContext) private var modelContext

    @AppStorage("completionDeleteDelay") private var completionDeleteDelay: Int = 5
    @AppStorage("appLocale") private var appLocale: String = "ko"

    @State private var showEditForm = false
    @State private var showActions = false
    @State private var showSubTodoPopover = false
    @State private var newSubTodoTitle = ""
    @State private var countdownSeconds: Int? = nil
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var draggingSubTodo: SubTodo? = nil
    @State private var subDropTargetID: UUID? = nil

    @FocusState private var subTodoFocused: Bool

    private var sortedSubTodos: [SubTodo] {
        todo.subTodos.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                CheckboxView(isCompleted: todo.isCompleted, size: DesignTokens.checkbox) {
                    withAnimation(DesignTokens.toggleSpring) { todo.isCompleted.toggle() }
                    Task { await RemindersSync.shared.push(todo) }
                }
                .padding(.top, 1)
                .disabled(isEditMode)
                .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)

                displayContent

                Spacer(minLength: 0)

                if let seconds = countdownSeconds {
                    CountdownBadge(seconds: seconds, total: completionDeleteDelay) {
                        withAnimation(DesignTokens.toggleSpring) { todo.isCompleted = false }
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    HStack(spacing: 2) {
                        if todo.subTodos.count < 20 {
                            addSubTodoButton
                        }
                        moreButton
                    }
                    .disabled(isEditMode)
                    .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
                    .transition(.opacity)
                }
            }
            .animation(DesignTokens.toggleSpring, value: isEditMode)

            if !todo.subTodos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedSubTodos) { subTodo in
                        let isDragging = draggingSubTodo?.id == subTodo.id
                        let isDropTarget = isEditMode
                            && subDropTargetID == subTodo.id
                            && draggingSubTodo?.id != subTodo.id
                        SubTodoRowView(subTodo: subTodo, isEditMode: isEditMode)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isDropTarget ? DesignTokens.systemBlue.opacity(0.10) : Color.clear)
                                    .padding(.horizontal, -2)
                            )
                            .contentShape(Rectangle())
                            .opacity(isEditMode && isDragging ? 0.35 : 1.0)
                            .scaleEffect(isEditMode && isDragging ? 0.98 : 1.0, anchor: .center)
                            .animation(DesignTokens.toggleSpring, value: isDragging)
                            .animation(DesignTokens.toggleSpring, value: isDropTarget)
                            .onDrag {
                                guard isEditMode else { return NSItemProvider() }
                                draggingSubTodo = subTodo
                                return NSItemProvider(object: subTodo.id.uuidString as NSString)
                            } preview: {
                                Text(subTodo.title)
                                    .font(DesignTokens.subTodoFont)
                                    .foregroundStyle(DesignTokens.textSubTodo)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ReorderDropDelegate<SubTodo>(
                                    target: subTodo,
                                    siblings: sortedSubTodos,
                                    isEditMode: isEditMode,
                                    // 같은 부모 todo 의 children 끼리만 reorder 허용.
                                    canReorder: { dragging in
                                        dragging.parent?.id == subTodo.parent?.id
                                    },
                                    setOrder: { $0.order = $1 },
                                    dragging: $draggingSubTodo,
                                    dropTargetID: $subDropTargetID
                                )
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
                .onDrop(of: [.text], delegate: ReorderDropResetDelegate<SubTodo>(
                    dragging: $draggingSubTodo,
                    dropTargetID: $subDropTargetID
                ))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 10, trailing: 6))
        .animation(DesignTokens.toggleSpring, value: countdownSeconds == nil)
        // 빈 제목으로 생성된 새 todo 는 row layoutSpring 등장이 settle 된 뒤 편집 폼을 연다.
        // 0 이면 row 가 그려지기 전에 popover 가 떠 anchor 가 점프하므로
        // DesignTokens.rowAppearSettleDelay 만큼 sleep 한다.
        .task {
            guard todo.title.isEmpty else { return }
            try? await Task.sleep(for: DesignTokens.rowAppearSettleDelay)
            if todo.title.isEmpty { showEditForm = true }
        }
        // 폼이 닫히면: 제목 비었으면 삭제, 아니면 (date/time 등 모든 변경 포함) push
        .onChange(of: showEditForm) { _, showing in
            guard !showing else { return }
            if todo.title.trimmingCharacters(in: .whitespaces).isEmpty {
                let rid = todo.reminderID
                withAnimation(DesignTokens.layoutSpring) { modelContext.delete(todo) }
                Task { await RemindersSync.shared.delete(reminderID: rid) }
            } else {
                Task { await RemindersSync.shared.push(todo) }
            }
        }
        .onChange(of: todo.isCompleted) { _, completed in
            if completed { startCountdown() } else { cancelCountdown() }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    // MARK: Display

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
        let locale = Locale(identifier: appLocale)
        let cal = Calendar.current
        let isKo = appLocale.hasPrefix("ko")

        var text: String
        if cal.isDateInToday(date) {
            text = isKo ? "오늘" : "Today"
        } else if cal.isDateInTomorrow(date) {
            text = isKo ? "내일" : "Tomorrow"
        } else if cal.isDateInYesterday(date) {
            text = isKo ? "어제" : "Yesterday"
        } else {
            text = fullDateString(date, locale: locale)
        }

        if let time = timeString(date, locale: locale) { text += ", \(time)" }
        if overdue { text += isKo ? " 지남" : " overdue" }
        return text
    }

    private func formattedDate(_ date: Date) -> String {
        fullDateString(date, locale: Locale(identifier: appLocale))
    }

    private func fullDateString(_ date: Date, locale: Locale) -> String {
        let df = DateFormatter()
        df.locale = locale
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        let isKo = locale.identifier.hasPrefix("ko")
        df.dateFormat = sameYear
            ? (isKo ? "M월 d일 (E)" : "MMM d (EEE)")
            : (isKo ? "yyyy년 M월 d일" : "MMM d, yyyy")
        return df.string(from: date)
    }

    private func timeString(_ date: Date, locale: Locale) -> String? {
        let cal = Calendar.current
        guard cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0 else { return nil }
        return date.formatted(.dateTime.hour().minute().locale(locale))
    }

    // MARK: Buttons

    private var addSubTodoButton: some View {
        Button {
            showSubTodoPopover = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.dotColor)
                .frame(width: DesignTokens.menuButton, height: DesignTokens.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSubTodoPopover, arrowEdge: .trailing) {
            subTodoPopover
        }
    }

    private var moreButton: some View {
        Button {
            showActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.dotColor)
                .frame(width: DesignTokens.menuButton, height: DesignTokens.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showActions, arrowEdge: .trailing) {
            actionsPopover
        }
        .popover(isPresented: $showEditForm, arrowEdge: .trailing) {
            EditTodoFormView(todo: todo)
        }
    }

    private var actionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showActions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    showEditForm = true
                }
            } label: {
                Label("수정", systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.textPrimary)

            Divider().padding(.horizontal, 8)

            Button {
                showActions = false
                let rid = todo.reminderID
                withAnimation(DesignTokens.layoutSpring) { modelContext.delete(todo) }
                Task { await RemindersSync.shared.delete(reminderID: rid) }
            } label: {
                Label("삭제", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.overdueColor)
        }
        .padding(.vertical, 4)
        .frame(width: 140)
    }

    // MARK: Sub-todo Popover

    private var subTodoPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("세부 할일")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMeta)
                    .tracking(0.3)
                Spacer()
                Button {
                    newSubTodoTitle = ""
                    showSubTodoPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.dotColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().padding(.horizontal, 8)

            TextField("제목", text: $newSubTodoTitle)
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
                    newSubTodoTitle = ""
                    showSubTodoPopover = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Button("추가") { submitSubTodo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSubTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .onAppear { subTodoFocused = true }
    }

    private func submitSubTodo() {
        let trimmed = newSubTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let sub = SubTodo(title: trimmed, order: todo.subTodos.count)
        sub.parent = todo
        withAnimation(DesignTokens.layoutSpring) {
            modelContext.insert(sub)
            todo.subTodos.append(sub)
        }
        newSubTodoTitle = ""
        showSubTodoPopover = false
    }

    // MARK: Countdown

    private func startCountdown() {
        cancelCountdown()
        let delay = completionDeleteDelay
        withAnimation(DesignTokens.toggleSpring) { countdownSeconds = delay }
        countdownTask = Task { @MainActor in
            do {
                for remaining in stride(from: delay - 1, through: 1, by: -1) {
                    try await Task.sleep(for: .seconds(1))
                    countdownSeconds = remaining
                }
                try await Task.sleep(for: .seconds(1))
                guard todo.isCompleted else { return }
                let rid = todo.reminderID
                withAnimation(DesignTokens.toggleSpring) { modelContext.delete(todo) }
                await RemindersSync.shared.delete(reminderID: rid)
            } catch { }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(DesignTokens.toggleSpring) { countdownSeconds = nil }
    }
}
