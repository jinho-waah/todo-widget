import SwiftUI

// 일정 생성/편집 popover. EditTodoFormView 의 캘린더 버전.
// SwiftData 바인딩이 없으므로 로컬 @State 로 폼을 들고, 저장 시 CalendarService 로 commit.
struct CalendarEventFormView: View {
    enum Mode {
        case create(Date)
        case edit(CalendarEvent)
    }

    let mode: Mode
    let onClose: () -> Void

    @State private var title: String
    @State private var calendarID: String?
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    @State private var calendars: [WritableCalendar] = []
    @FocusState private var titleFocused: Bool

    private let service = CalendarService.shared

    init(mode: Mode, onClose: @escaping () -> Void) {
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create(let day):
            let s = Self.defaultStart(on: day)
            _title = State(initialValue: "")
            _calendarID = State(initialValue: CalendarService.shared.defaultCalendarID)
            _isAllDay = State(initialValue: false)
            _start = State(initialValue: s)
            _end = State(initialValue: s.addingTimeInterval(3600))
            _notes = State(initialValue: "")
        case .edit(let event):
            _title = State(initialValue: event.title)
            _calendarID = State(initialValue: event.calendarID)
            _isAllDay = State(initialValue: event.isAllDay)
            _start = State(initialValue: event.start)
            _end = State(initialValue: event.end)
            _notes = State(initialValue: event.notes ?? "")
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    private var currentCalendar: WritableCalendar? {
        calendars.first { $0.id == calendarID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(title: isNew ? "새 일정" : "수정", onClose: nil)
            Divider().padding(.horizontal, 8)

            TextField("제목", text: $title)
                .textFieldStyle(.plain)
                .font(DesignTokens.todoTitleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .focused($titleFocused)
                .onSubmit(save)

            Divider().padding(.horizontal, 8)
            calendarRow

            Divider().padding(.horizontal, 8)
            allDayRow

            Divider().padding(.horizontal, 8)
            dateRow(label: "시작", isStart: true, showTime: !isAllDay)

            Divider().padding(.horizontal, 8)
            dateRow(label: "종료", isStart: false, showTime: !isAllDay)

            Divider().padding(.horizontal, 8)
            TextField("메모 추가", text: $notes, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(DesignTokens.descFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            Divider().padding(.horizontal, 8)
            buttons
        }
        .padding(.vertical, 4)
        .frame(width: 270)
        .onAppear {
            calendars = service.writableCalendars()
            if calendarID == nil { calendarID = service.defaultCalendarID }
            if isNew { titleFocused = true }
        }
    }

    // MARK: Rows

    private var calendarRow: some View {
        Menu {
            ForEach(calendars) { cal in
                Button {
                    calendarID = cal.id
                } label: {
                    // 각 캘린더의 색을 점으로 표시(선택된 것은 체크 표시된 점).
                    Label {
                        Text(cal.title)
                    } icon: {
                        Image(systemName: cal.id == calendarID ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(cal.color)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 14)
                Circle()
                    .fill(currentCalendar?.color ?? DesignTokens.systemBlue)
                    .frame(width: 9, height: 9)
                Text(currentCalendar?.title ?? "캘린더 선택")
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

    private var allDayRow: some View {
        Toggle(isOn: $isAllDay.animation(DesignTokens.toggleSpring)) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 14)
                Text("종일")
                    .font(DesignTokens.descFont)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func dateRow(label: String, isStart: Bool, showTime: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DesignTokens.descFont)
                .foregroundStyle(DesignTokens.textMeta)
                .frame(width: 34, alignment: .leading)

            DatePicker(
                "",
                selection: isStart ? startBinding : endBinding,
                displayedComponents: showTime ? [.date, .hourAndMinute] : [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, .userPreferred)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var buttons: some View {
        HStack {
            if !isNew {
                Button("삭제", role: .destructive, action: delete)
                    .buttonStyle(.glass)
                    .foregroundStyle(DesignTokens.overdueColor)
            } else {
                Button("취소") { onClose() }
                    .buttonStyle(.glass)
            }
            Spacer()
            Button(isNew ? "추가" : "저장", action: save)
                .buttonStyle(.glassProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Actions

    /// 시작을 옮기면 종료도 같은 간격으로 따라온다 (기간 유지).
    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { newValue in
                let delta = newValue.timeIntervalSince(start)
                start = newValue
                end = end.addingTimeInterval(delta)
            }
        )
    }

    /// 종료는 시작보다 빨라지지 않도록 clamp.
    private var endBinding: Binding<Date> {
        Binding(
            get: { end },
            set: { end = max($0, start) }
        )
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create:
            service.createEvent(
                title: trimmed, start: start, end: max(end, start), isAllDay: isAllDay,
                calendarID: calendarID, notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
        case .edit(let event):
            service.update(
                eventID: event.eventID, title: trimmed, start: start, end: max(end, start), isAllDay: isAllDay,
                calendarID: calendarID, notes: cleanNotes.isEmpty ? nil : cleanNotes
            )
        }
        onClose()
    }

    private func delete() {
        if case .edit(let event) = mode {
            service.delete(eventID: event.eventID)
        }
        onClose()
    }

    private static func defaultStart(on day: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) {
            // 오늘이면 다음 정시로.
            let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            return cal.date(bySetting: .minute, value: 0, of: next) ?? next
        }
        // 다른 날이면 09:00.
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
