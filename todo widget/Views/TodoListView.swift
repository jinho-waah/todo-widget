import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Todo.order), SortDescriptor(\Todo.createdAt)])
    private var todos: [Todo]

    @State private var store = TodoListStore()

    /// 헤더(상하 패딩 18+12) + divider(0.5) + 리스트 bottom padding(10) 을 합친 chrome 높이.
    /// 윈도우 max(980) 에서 이만큼 빼서 ScrollView 의 cap 으로 사용.
    private var chromeHeight: CGFloat { 60 }
    private var maxListHeight: CGFloat { DesignTokens.widgetMaxHeight - chromeHeight }

    var body: some View {
        // Widget 본체는 intrinsic height (todo 개수에 따라 결정, 단 max 980).
        let widget = VStack(spacing: 0) {
            HeaderView(
                isEditMode: isEditModeBinding,
                onAdd: { store.send(.addTodo(todos: todos, context: modelContext)) }
            )
            Rectangle()
                .fill(DesignTokens.headerDivider)
                .frame(height: 0.5)
                .padding(.horizontal, 4)
            // 권한이 없으면 헤더 바로 아래에 banner.
            // notDetermined/requestFailed 는 실제 권한 요청을 먼저 실행하고,
            // denied 는 사용자가 이미 거부한 상태이므로 System Settings 로 보낸다.
            if store.showsPermissionBanner {
                remindersPermissionBanner
            }
            scrollableTodoList
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
            store.send(.widgetHeightChanged(height))
        }

        // 위젯이 윈도우 안에서 항상 top-leading 에 위치하도록.
        // 윈도우는 위젯 height 에 맞춰 즉시 resize 되므로 보통은 빈 영역이 없지만,
        // 초기 launch 한 프레임이나 resize 직전 프레임에 빈 영역이 있더라도 위쪽 정렬.
        return widget
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task {
                // 미리 알림 양방향 sync 시작. 권한이 아직 결정되지 않은 상태라면
                // 자동 prompt 대신 배너 클릭에서 명시적으로 요청한다.
                store.send(.startSync(modelContext))
            }
    }

    // MARK: Permission Banner

    /// 미리 알림 권한이 거부된 상태에서 헤더 아래에 노출. 클릭 시 System Settings 의
    /// Privacy → Reminders pane 으로 직접 이동.
    private var remindersPermissionBanner: some View {
        Button {
            store.send(.permissionBannerTapped)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.systemRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.remindersPermissionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(store.remindersPermissionSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(DesignTokens.systemRed.opacity(0.10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Scrollable Todo List

    /// todoListSection 을 감싸는 ScrollView.
    /// `.fixedSize(vertical: true)` 가 ScrollView 를 content 의 intrinsic height 로 자라게
    /// 만들고, `.frame(maxHeight:)` 가 그 높이를 max 로 cap → cap 미만이면 스크롤 없이
    /// 콘텐츠 그대로, 넘으면 ScrollView 가 max 에서 멈추고 내부 스크롤 활성화.
    private var scrollableTodoList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // top/bottom 앵커 — chevron 클릭 시 proxy.scrollTo 의 타깃.
                Color.clear.frame(height: 0).id(ScrollAnchor.top)
                todoListSection
                Color.clear.frame(height: 0).id(ScrollAnchor.bottom)
            }
            .frame(maxHeight: maxListHeight)
            .fixedSize(horizontal: false, vertical: true)
            // + 로 새 todo 가 추가됐을 때 자동으로 맨 아래로 스크롤. todos.count 증가만
            // 트리거 (삭제·재정렬은 무관). row 가 layout 되도록 한 frame 기다린 뒤 스크롤.
            .onChange(of: todos.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
                    }
                }
            }
            // 위/아래 양쪽으로 가려진 콘텐츠가 있는지 한 번에 추적해 두 affordance 를 동시 갱신.
            .onScrollGeometryChange(for: ScrollEdges.self) { geo in
                ScrollEdges(
                    above: geo.contentOffset.y > 1,
                    below: geo.contentSize.height - (geo.contentOffset.y + geo.containerSize.height) > 1
                )
            } action: { _, newValue in
                store.send(.setScrollEdges(above: newValue.above, below: newValue.below))
            }
            // 위/아래 fade + chevron — 해당 방향에 가려진 콘텐츠가 있을 때만 노출.
            // chevron 은 클릭 시 해당 방향 끝으로 스크롤.
            .overlay(alignment: .top) {
                scrollEdgeIndicator(direction: .up, visible: store.state.hasMoreAbove) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                scrollEdgeIndicator(direction: .down, visible: store.state.hasMoreBelow) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// 위/아래 공용 affordance — 그라데이션 fade + tappable chevron.
    /// chevron 영역은 충분히 큰 hit area (height 56) 를 가지며 tap 시 onTap 콜백 실행.
    /// fade 자체는 hit-test 통과 (스크롤 방해 X), chevron 만 hit-test 가능.
    @ViewBuilder
    private func scrollEdgeIndicator(
        direction: ScrollEdgeDirection,
        visible: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: direction == .up ? .top : .bottom) {
            // 콘텐츠를 살짝 가리는 fade — 가장자리 쪽이 진하게. hit-test 통과.
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.18)],
                startPoint: direction == .up ? .bottom : .top,
                endPoint:   direction == .up ? .top    : .bottom
            )
            .frame(height: 56)
            .allowsHitTesting(false)

            // 충분히 큰 tap target — chevron 자체는 작지만 주변 패딩 포함 32×32 가 클릭 영역.
            Button(action: onTap) {
                Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(direction == .up ? .top : .bottom, 2)
        }
        .opacity(visible ? 1 : 0)
        // visible == false 일 땐 클릭 자체를 막음 (스크롤 끝에서 의미 없는 tap 방지).
        .allowsHitTesting(visible)
    }

    // MARK: Todo List

    private var todoListSection: some View {
        Group {
            if todos.isEmpty {
                Text("할일을 추가해보세요")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
            } else {
                // ScrollView/onGeometryChange/listContentHeight 피드백 루프 제거 →
                // 단일 withAnimation transaction 만으로 row 등장/소멸 + 윈도우 contentSize 가
                // 한 번의 spring 으로 매끄럽게 변함.
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        VStack(spacing: 0) {
                            TodoRowView(todo: todo, isEditMode: store.state.isEditMode)
                            if todo.id != todos.last?.id {
                                Rectangle()
                                    .fill(DesignTokens.divider)
                                    .frame(height: 0.5)
                                    .padding(.leading, DesignTokens.subIndent + 10)
                            }
                        }
                        .reorderableRow(
                            item: todo,
                            siblings: todos,
                            isEditMode: store.state.isEditMode,
                            dragging: draggingTodoBinding,
                            dropTargetID: dropTargetIDBinding
                        ) {
                            Text(todo.title.isEmpty ? "새 할일" : todo.title)
                                .font(DesignTokens.todoTitleFont)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        // 추가/삭제 대칭 — 양쪽 모두 opacity + scale(0.96, anchor: top).
                        // 비대칭이면 (삭제는 opacity-only) 사라질 때 끊겨 보임.
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
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
                    dragging: draggingTodoBinding,
                    dropTargetID: dropTargetIDBinding
                ))
            }
        }
    }

    // MARK: Bindings

    private var isEditModeBinding: Binding<Bool> {
        Binding(
            get: { store.state.isEditMode },
            set: { store.send(.setEditMode($0)) }
        )
    }

    private var draggingTodoBinding: Binding<Todo?> {
        Binding(
            get: { store.state.draggingTodo },
            set: { store.state.draggingTodo = $0 }
        )
    }

    private var dropTargetIDBinding: Binding<UUID?> {
        Binding(
            get: { store.state.dropTargetID },
            set: { store.state.dropTargetID = $0 }
        )
    }
}

// MARK: - Widget Height Preference

// 스크롤 affordance 의 위/아래 가시성을 한 번의 onScrollGeometryChange 에서 함께 계산하기 위한 묶음.
private struct ScrollEdges: Equatable {
    var above: Bool
    var below: Bool
}

private enum ScrollEdgeDirection { case up, down }

// ScrollViewReader 의 scrollTo 타깃 식별자.
private enum ScrollAnchor: Hashable { case top, bottom }

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
