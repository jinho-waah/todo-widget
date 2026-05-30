import SwiftUI

struct ReminderListPickerMenu<LabelContent: View>: View {
    let lists: [ReminderList]
    let currentListID: String?
    let onSelectList: (String) -> Void
    let onCreateList: () -> Void
    @ViewBuilder let label: (ReminderList?) -> LabelContent

    private var currentList: ReminderList? {
        lists.first { $0.id == currentListID }
    }

    var body: some View {
        Menu {
            if !lists.isEmpty {
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
            }

            Button(action: onCreateList) {
                Label("새 목록 생성", systemImage: "plus")
            }
        } label: {
            label(currentList)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
