import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Todo.order), SortDescriptor(\Todo.createdAt)])
    private var todos: [Todo]

    @State private var isEditMode = false
    @State private var draggingTodo: Todo? = nil
    @State private var dropTargetID: UUID? = nil

    var body: some View {
        // Widget 본체는 intrinsic height (todo 개수에 따라 결정).
        let widget = VStack(spacing: 0) {
            HeaderView(isEditMode: $isEditMode, onAdd: addTodo)
            Rectangle()
                .fill(DesignTokens.headerDivider)
                .frame(height: 0.5)
                .padding(.horizontal, 4)
            todoListSection
        }
        .frame(width: DesignTokens.widgetWidth)
        .background(GlassCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
        // Widget 의 intrinsic height 를 매 프레임 측정해 AppDelegate 로 통지.
        // AppDelegate 는 통지를 받아 윈도우 frame 을 즉시 (animate:false) 업데이트
        // 하면서 origin.y = anchorTopY - newHeight 로 top 을 항상 고정한다.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WidgetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(WidgetHeightKey.self) { height in
            NotificationCenter.default.post(name: .widgetContentHeightChanged, object: height)
        }

        // 위젯이 윈도우 안에서 항상 top-leading 에 위치하도록.
        // 윈도우는 위젯 height 에 맞춰 즉시 resize 되므로 보통은 빈 영역이 없지만,
        // 초기 launch 한 프레임이나 resize 직전 프레임에 빈 영역이 있더라도 위쪽 정렬.
        return widget
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task {
                // 미리 알림 양방향 sync 시작 (권한 요청 → 전용 list 확보 → 초기 pull)
                // RemindersSync.start 는 내부에 didStart 가드가 있어 중복 호출 안전.
                RemindersSync.shared.start(with: modelContext)
            }
            // 편집 모드 진입/종료를 AppDelegate 로 통지 → 윈도우 background 드래그를
            // 편집 모드 동안 비활성화해 todo 드래그-재정렬과의 충돌을 막는다.
            .onChange(of: isEditMode) { _, editing in
                NotificationCenter.default.post(name: .widgetEditModeChanged, object: editing)
            }
    }

    // MARK: Todo List

    private var todoListSection: some View {
        Group {
            if todos.isEmpty {
                Text("할일을 추가해보세요")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
            } else {
                // ScrollView/onGeometryChange/listContentHeight 피드백 루프 제거 →
                // 단일 withAnimation transaction 만으로 row 등장/소멸 + 윈도우 contentSize 가
                // 한 번의 spring 으로 매끄럽게 변함.
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        let isDragging = draggingTodo?.id == todo.id
                        let isDropTarget = isEditMode
                            && dropTargetID == todo.id
                            && draggingTodo?.id != todo.id
                        VStack(spacing: 0) {
                            TodoRowView(todo: todo, isEditMode: isEditMode)
                            if todo.id != todos.last?.id {
                                Rectangle()
                                    .fill(DesignTokens.divider)
                                    .frame(height: 0.5)
                                    .padding(.leading, DesignTokens.subIndent + 10)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isDropTarget ? DesignTokens.systemBlue.opacity(0.10) : Color.clear)
                                .padding(.horizontal, -4)
                        )
                        // row 의 빈(글자 없는) 영역까지 hit-test 가 닿도록 컨테이너
                        // 전체를 클릭 가능 영역으로 지정. 이게 없으면 SwiftUI 가 글자/
                        // 버튼 같은 그려진 픽셀에만 hit-test 를 허용해 드래그가 안 잡힘.
                        .contentShape(Rectangle())
                        .opacity(isEditMode && isDragging ? 0.35 : 1.0)
                        .scaleEffect(isEditMode && isDragging ? 0.98 : 1.0, anchor: .center)
                        .animation(DesignTokens.toggleSpring, value: isDragging)
                        .animation(DesignTokens.toggleSpring, value: isDropTarget)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                        ))
                        .onDrag {
                            guard isEditMode else { return NSItemProvider() }
                            draggingTodo = todo
                            return NSItemProvider(object: todo.id.uuidString as NSString)
                        } preview: {
                            Text(todo.title.isEmpty ? "새 할일" : todo.title)
                                .font(DesignTokens.todoTitleFont)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .onDrop(
                            of: [.text],
                            delegate: ReorderDropDelegate<Todo>(
                                target: todo,
                                siblings: todos,
                                isEditMode: isEditMode,
                                canReorder: { _ in true },
                                setOrder: { $0.order = $1 },
                                dragging: $draggingTodo,
                                dropTargetID: $dropTargetID
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                // @Query 가 비동기로 결과를 다시 emit 하면 add/delete/reorder 가
                // withAnimation 트랜잭션 밖에서 일어나 transition/위치 이동이
                // 튀듯 적용된다. 정렬된 id 시퀀스를 value 로 주면 SwiftUI 가
                // 그 변화 자체에 layoutSpring 을 묶어 row 등장·소멸·재정렬을
                // sub-todo 와 동일한 spring 으로 부드럽게 처리한다.
                .animation(DesignTokens.layoutSpring, value: todos.map(\.id))
                // 리스트 바깥으로 빠져나가 drop 이 row delegate 에 도달 못 한 채 끝난
                // 경우에도 dragging/highlight 상태를 확실히 정리한다.
                .onDrop(of: [.text], delegate: ReorderDropResetDelegate<Todo>(
                    dragging: $draggingTodo,
                    dropTargetID: $dropTargetID
                ))
            }
        }
    }

    // MARK: Actions

    private func addTodo() {
        withAnimation(DesignTokens.layoutSpring) {
            let newTodo = Todo(title: "", order: todos.count)
            modelContext.insert(newTodo)
        }
    }
}

// MARK: - Widget Height Preference

private struct WidgetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    TodoListView()
        .modelContainer(for: [Todo.self, SubTodo.self], inMemory: true)
}
