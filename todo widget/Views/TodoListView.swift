import SwiftUI
import SwiftData

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
                RemindersPermissionBanner(
                    title: store.remindersPermissionTitle,
                    subtitle: store.remindersPermissionSubtitle,
                    onTap: { store.send(.permissionBannerTapped) }
                )
            }
            scrollableTodoList
        }
        .frame(width: DesignTokens.widgetWidth)
        .background(GlassCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
        // Widget 의 intrinsic height 를 매 프레임 측정해 AppDelegate 로 통지.
        // AppDelegate 는 통지를 받아 윈도우 frame 을 즉시 (animate:false) 업데이트
        // 하면서 origin.y = anchorTopY - newHeight 로 top 을 항상 고정한다.
        //
        // macOS 14+ 의 `.onGeometryChange` 를 사용. 이전엔 `.background(GeometryReader)` +
        // PreferenceKey 패턴을 썼지만 macOS 26 + `.glassEffect` 와 조합 시 첫 측정이 0 으로
        // 떨어진 뒤 reflow 가 발생하지 않는 경우가 있어 교체.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            guard newHeight > 0 else { return }
            store.send(.widgetHeightChanged(newHeight))
        }

        return widget
            .task {
                // 미리 알림 양방향 sync 시작. 권한이 아직 결정되지 않은 상태라면
                // 자동 prompt 대신 배너 클릭에서 명시적으로 요청한다.
                store.send(.startSync(modelContext))
            }
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
                TodoListContentSection(
                    todos: todos,
                    isEditMode: store.state.isEditMode,
                    draggingTodo: draggingTodoBinding,
                    dropTargetID: dropTargetIDBinding
                )
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
                ScrollEdgeIndicator(direction: .up, visible: store.state.hasMoreAbove) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                ScrollEdgeIndicator(direction: .down, visible: store.state.hasMoreBelow) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
                    }
                }
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

// 스크롤 affordance 의 위/아래 가시성을 한 번의 onScrollGeometryChange 에서 함께 계산하기 위한 묶음.
private struct ScrollEdges: Equatable {
    var above: Bool
    var below: Bool
}

// ScrollViewReader 의 scrollTo 타깃 식별자.
private enum ScrollAnchor: Hashable { case top, bottom }

#Preview {
    TodoListView()
        .modelContainer(for: [Todo.self, SubTodo.self], inMemory: true)
}
