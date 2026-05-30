import SwiftUI
import SwiftData
import AppKit

struct TodoRowView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var todo: Todo
    let isEditMode: Bool

    @AppStorage("completionDeleteDelay") private var completionDeleteDelay: Int = 5

    @State private var store = TodoRowStore()

    private var sortedSubTodos: [SubTodo] {
        todo.subTodos.sorted { $0.order < $1.order }
    }

    private var reminderAccentColor: Color {
        RemindersSync.shared.color(forListID: todo.reminderListID) ?? DesignTokens.systemBlue
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

                TodoRowDisplayContent(
                    title: todo.title,
                    todoDescription: todo.todoDescription,
                    dueDate: todo.dueDate,
                    isCompleted: todo.isCompleted,
                    reminderAccentColor: reminderAccentColor
                )

                Spacer(minLength: 0)

                trailingActions
                    .disabled(isEditMode)
                    .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
                    .transition(.opacity)
            }
            .animation(DesignTokens.toggleSpring, value: isEditMode)

            if !todo.subTodos.isEmpty {
                SubTodoListSection(
                    subTodos: sortedSubTodos,
                    isEditMode: isEditMode,
                    draggingSubTodo: draggingSubTodoBinding,
                    dropTargetID: subDropTargetIDBinding
                )
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

    // MARK: Buttons

    @ViewBuilder
    private var trailingActions: some View {
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
    }

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
        SubTodoAddPopover(
            title: newSubTodoTitleBinding,
            onCancel: { store.send(.cancelSubTodo) },
            onSubmit: submitSubTodo
        )
    }

    private func submitSubTodo() {
        store.send(.submitSubTodo(todo: todo, context: modelContext))
    }
}
