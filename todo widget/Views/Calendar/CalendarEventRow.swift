import SwiftUI

// 아젠다의 단일 일정 행. 캘린더 색 세로 바 + 제목 + 시간/위치.
// 행을 탭하면 편집 popover(CalendarEventFormView)가 이 행에 anchor 되어 열린다.
struct CalendarEventRow: View {
    let event: CalendarEvent
    @State private var showEdit = false

    var body: some View {
        Button {
            showEdit = true
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.color)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(DesignTokens.todoTitleFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(CalendarFormatters.timeLabel(for: event))
                            .font(DesignTokens.dateFont)
                            .foregroundStyle(DesignTokens.textSecondary)
                        if let location = event.location, !location.isEmpty {
                            Text("· \(location)")
                                .font(DesignTokens.dateFont)
                                .foregroundStyle(DesignTokens.textMeta)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showEdit, arrowEdge: .leading) {
            CalendarEventFormView(mode: .edit(event)) { showEdit = false }
        }
    }
}
