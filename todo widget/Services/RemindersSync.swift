import AppKit
import EventKit
import OSLog
import SwiftData
import SwiftUI

// 로컬 SwiftData (Todo) ↔ macOS 미리 알림(EKReminder) 양방향 동기화.
//
// RemindersSync 는 앱에서 호출하는 facade 역할만 맡고, EventKit 접근은
// RemindersEventStore, 로컬-원격 병합은 RemindersReconciler 에 위임한다.
@MainActor
@Observable
final class RemindersSync {
    @ObservationIgnored static let shared = RemindersSync()

    @ObservationIgnored let eventStore = RemindersEventStore()
    @ObservationIgnored private let reconciler = RemindersReconciler()
    @ObservationIgnored private weak var modelContext: ModelContext?
    @ObservationIgnored var observer: NSObjectProtocol?
    @ObservationIgnored var isRequestingAccess = false

    var status: RemindersSyncStatus = .unknown
    var lastRequestError: String?

    @ObservationIgnored private(set) var isApplyingRemoteChange = false

    private init() {}

    func start(with context: ModelContext) {
        modelContext = context
        Task { await bootstrap(requestIfNeeded: false) }
    }

    func refresh() async {
        guard !isRequestingAccess else { return }
        await bootstrap(requestIfNeeded: false)
    }

    func requestAccessFromUser() async {
        await bootstrap(requestIfNeeded: true)
    }

    var defaultListID: String? {
        eventStore.defaultListID
    }

    func availableLists() -> [ReminderList] {
        eventStore.availableLists()
    }

    func createList(named title: String, color: NSColor) async -> String? {
        await eventStore.createList(named: title, color: color)
    }

    func color(forListID listID: String?) -> Color? {
        eventStore.color(forListID: listID)
    }

    func move(_ todo: Todo, toListID listID: String?) async {
        todo.reminderListID = listID
        await push(todo)
    }

    func pullAndReconcile() async {
        guard eventStore.hasAccess, let modelContext else {
            remindersLog.debug("pullAndReconcile skipped — hasAccess=\(self.eventStore.hasAccess, privacy: .public)")
            return
        }

        guard let reminders = await eventStore.fetchAllReminders() else {
            remindersLog.warning("pull skipped — reminders fetch returned nil")
            return
        }
        remindersLog.info("pull — \(reminders.count) reminders across \(self.eventStore.calendarCount) reminder lists")

        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        await reconciler.reconcile(
            reminders: reminders,
            in: modelContext,
            pruneMissingRemoteItems: false,
            pushUnsyncedTodo: { [weak self] todo in
                await self?.push(todo, skipGuard: true)
            }
        )
    }

    func push(_ todo: Todo) async {
        await push(todo, skipGuard: false)
    }

    func delete(reminderID: String?) async {
        eventStore.delete(reminderID: reminderID)
    }

    private func bootstrap(requestIfNeeded: Bool) async {
        switch await resolveAccess(requestIfNeeded: requestIfNeeded) {
        case .granted:
            break
        case .blocked:
            return
        }

        do {
            try eventStore.ensureDefaultCalendar()
        } catch {
            remindersLog.error("ensureCalendar failed: \(String(describing: error), privacy: .public)")
            return
        }

        installStoreChangeObserverIfNeeded()
        await pullAndReconcile()
    }

    private func push(_ todo: Todo, skipGuard: Bool) async {
        guard eventStore.hasAccess else {
            remindersLog.debug("push skipped — no access (todo='\(todo.title, privacy: .public)')")
            return
        }
        if !skipGuard, isApplyingRemoteChange { return }
        if todo.title.trimmingCharacters(in: .whitespaces).isEmpty { return }

        do {
            try eventStore.save(todo)
        } catch RemindersEventStoreError.missingCalendar {
            remindersLog.warning("push skipped — no resolved calendar (todo='\(todo.title, privacy: .public)')")
        } catch {
            remindersLog.error("store.save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func installStoreChangeObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            remindersLog.debug("EKEventStoreChanged received")
            Task { @MainActor in await self?.pullAndReconcile() }
        }
    }

    func resetEventStoreAfterPermissionChange() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        eventStore.recreateStore()
    }
}
