import SwiftUI

// Todo row 의 `...` 메뉴.
// 상단 picker chip (현재 매핑된 reminder list — 색 원 + 제목 + chevron) 을 누르면
// 시스템 native dropdown 으로 list 후보가 펼쳐지고, 선택하면 해당 list 로 이동.
//
// SubTodo 는 reminder 매핑 자체가 없으므로 더 단순한 RowActionsPopover 를 그대로 쓴다.

struct TodoActionsPopover: View {
    let lists: [ReminderList]
    /// 현재 todo 가 속한 calendarIdentifier (nil 이면 매칭되는 list 없음).
    let currentListID: String?
    let onEdit: () -> Void
    let onSelectList: (String) -> Void
    let onCreateList: () -> Void
    let onDelete: () -> Void

    private var currentList: ReminderList? {
        lists.first { $0.id == currentListID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !lists.isEmpty {
                listPicker
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                Divider().padding(.horizontal, 8)
            }

            actionButton(label: "수정", icon: "pencil", color: DesignTokens.textPrimary, action: onEdit)
            Divider().padding(.horizontal, 8)
            actionButton(label: "삭제", icon: "trash", color: DesignTokens.overdueColor, action: onDelete)
        }
        .padding(.vertical, 4)
        .frame(width: 180)
    }

    // MARK: List Picker

    private var listPicker: some View {
        Menu {
            ForEach(lists) { list in
                Button {
                    onSelectList(list.id)
                } label: {
                    if list.id == currentListID {
                        Label(list.title, systemImage: "checkmark")
                    } else {
                        Text(list.title)
                    }
                }
            }
            Divider()
            Button(action: onCreateList) {
                Label("새 목록 생성", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(currentList?.color ?? DesignTokens.systemBlue)
                    .frame(width: 10, height: 10)
                Text(currentList?.title ?? "기본 목록")
                    .font(DesignTokens.subTodoFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMeta)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DesignTokens.buttonStroke, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: Action Button (수정 / 삭제)

    private func actionButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
    }
}
