import SwiftUI

// 캘린더 탭 콘텐츠 (itsycal 스타일). **순수 콘텐츠** — 윈도우 높이 측정/글래스/width 는
// 셸(TodoListView)이 소유하고, 이 뷰는 그 측정 서브트리 안에서 swap 된다.
//
// 구성: (권한 배너) → 월 네비 → 그리드(고정) → divider → 아젠다 ScrollView(cap).
struct CalendarView: View {
    /// 아젠다 ScrollView 의 maxHeight cap (셸이 윈도우 max 에서 캘린더 chrome 을 빼서 전달).
    let agendaMaxHeight: CGFloat

    @State private var store = CalendarStore()
    @State private var showCreate = false
    @State private var agendaEdges = AgendaEdges()

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            if store.showsPermissionBanner {
                RemindersPermissionBanner(
                    title: store.permissionTitle,
                    subtitle: store.permissionSubtitle,
                    onTap: { store.send(.permissionBannerTapped) }
                )
            }

            monthNav

            CalendarGridView(
                displayedMonth: store.state.displayedMonth,
                selectedDate: store.state.selectedDate,
                service: store.service,
                onSelectDay: { store.send(.selectDay($0)) }
            )

            Rectangle()
                .fill(DesignTokens.divider)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            agenda
        }
        .padding(.bottom, 10)
        .task { store.send(.start) }
    }

    // MARK: Month navigation

    private var monthNav: some View {
        HStack(spacing: 4) {
            navButton("chevron.left") { store.send(.prevMonth) }

            Text(CalendarFormatters.monthTitle.string(from: store.state.displayedMonth))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            if !calendar.isDate(store.state.displayedMonth, equalTo: Date(), toGranularity: .month) {
                navButton("largecircle.fill.circle", size: 11) { store.send(.jumpToToday) }
                    .help("오늘로")
            }
            navButton("chevron.right") { store.send(.nextMonth) }

            navButton("plus") { showCreate = true }
                .popover(isPresented: $showCreate, arrowEdge: .top) {
                    CalendarEventFormView(mode: .create(store.state.selectedDate)) { showCreate = false }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func navButton(_ icon: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Agenda (선택일부터 다가오는 일정)

    private var upcoming: [CalendarEvent] {
        store.service.upcomingEvents(from: store.state.selectedDate)
    }

    private var groupedUpcoming: [(day: Date, events: [CalendarEvent])] {
        // 선택일보다 이전에 시작한(다중일/지난) 일정은 선택일 섹션 아래로 clamp —
        // "선택일부터 다가오는 일정" 에 과거 날짜 헤더가 위로 올라오지 않도록.
        let from = store.state.selectedDate
        let groups = Dictionary(grouping: upcoming) { max(calendar.startOfDay(for: $0.start), from) }
        return groups.keys.sorted().map { (day: $0, events: groups[$0] ?? []) }
    }

    // 미리 알림 리스트와 동일한 "최대 높이 cap + 내부 스크롤" 패턴. cap(≈8행) 미만이면
    // 그대로, 넘으면 스크롤하며 위/아래 fade+chevron affordance 를 띄운다.
    private var agenda: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(AgendaAnchor.top)
                VStack(alignment: .leading, spacing: 0) {
                    if store.service.status == .granted, upcoming.isEmpty {
                        emptyAgenda
                    } else {
                        ForEach(groupedUpcoming, id: \.day) { group in
                            agendaSection(day: group.day, events: group.events)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 날짜를 바꾸면 아젠다 내용이 천천히 바뀌도록 — 그리드 disc 의 toggleSpring 보다 느리게.
                .animation(.easeInOut(duration: 0.45), value: store.state.selectedDate)
                Color.clear.frame(height: 0).id(AgendaAnchor.bottom)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: agendaMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            // 날짜를 바꾸면 맨 위(가장 가까운 일정)로 스크롤.
            .onChange(of: store.state.selectedDate) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(AgendaAnchor.top, anchor: .top)
                }
            }
            .onScrollGeometryChange(for: AgendaEdges.self) { geo in
                AgendaEdges(
                    above: geo.contentOffset.y > 1,
                    below: geo.contentSize.height - (geo.contentOffset.y + geo.containerSize.height) > 1
                )
            } action: { _, newValue in
                withAnimation(.easeOut(duration: 0.18)) { agendaEdges = newValue }
            }
            .overlay(alignment: .top) {
                ScrollEdgeIndicator(direction: .up, visible: agendaEdges.above) {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(AgendaAnchor.top, anchor: .top) }
                }
            }
            .overlay(alignment: .bottom) {
                ScrollEdgeIndicator(direction: .down, visible: agendaEdges.below) {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(AgendaAnchor.bottom, anchor: .bottom) }
                }
            }
        }
    }

    private func agendaSection(day: Date, events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sectionTitle(for: day))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(calendar.isDateInToday(day) ? DT.blueText : DesignTokens.textMeta)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ForEach(events) { event in
                CalendarEventRow(event: event)
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        if calendar.isDateInToday(day) { return "오늘 · " + CalendarFormatters.sectionDate.string(from: day) }
        if calendar.isDateInTomorrow(day) { return "내일 · " + CalendarFormatters.sectionDate.string(from: day) }
        return CalendarFormatters.sectionDate.string(from: day)
    }

    private var emptyAgenda: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DesignTokens.textMeta)
                Text("다가오는 일정이 없습니다")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }
}

// 아젠다 스크롤 affordance 의 위/아래 가시성 묶음 + scrollTo 타깃.
private struct AgendaEdges: Equatable {
    var above = false
    var below = false
}

private enum AgendaAnchor: Hashable { case top, bottom }
