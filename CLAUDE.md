# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Pure Xcode project (`objectVersion` 77, file-system-synchronized groups). No build scripts; one SPM dependency (`soffes/HotKey`, resolves 0.2.1). macOS deployment target **26.4** — the UI relies on Liquid Glass `.glassEffect`. Project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (so types are MainActor-isolated unless opted out), App Sandbox on, `LSUIElement = YES`.

- **Build**: `Cmd+B`, or `xcodebuild -project "todo widget.xcodeproj" -scheme "todo widget" build` (the scheme's default config is **Release**; add `-configuration Debug` for a debug build)
- **Run**: `Cmd+R`
- **Tests**: `Cmd+U`, or `xcodebuild test -project "todo widget.xcodeproj" -scheme "todo widget"`
- **Single test**: `xcodebuild test -project "todo widget.xcodeproj" -scheme "todo widget" -only-testing:"todo widgetTests/<Suite>/<testName>"`

Targets: app `todo widget`, unit `todo widgetTests` (**Swift Testing** — `import Testing`, `@Test`, `#expect`/`#require`), UI `todo widgetUITests` (XCTest, stock launch-only stubs). The compiled module is `todo_widget` (underscore) even though target names contain a space. Current unit coverage is only `RemindersDateMapper`; nothing tests the design system or views.

There is also an `AGENTS.md` (the Codex equivalent of this file). Keep the architecture description in `AGENTS.md` in sync with edits here.

## Architecture

macOS SwiftUI app rendered as a **borderless floating widget** (LSUIElement, no Dock icon), summoned/dismissed via a global **⌃+1** hotkey. Two tabs — **Reminders** and **Calendar** — live inside one manually-sized, top-anchored `NSWindow`. SwiftData backs the todo list; macOS Reminders and macOS Calendar are bridged through two parallel `@MainActor @Observable` singletons (`RemindersSync.shared`, `CalendarService.shared`). Every stateful view delegates its logic to a per-view **State + Intent store** in `Stores/`.

### Data layer (`Models/`)

Two SwiftData `@Model` classes plus a versioned-schema scaffold. No `@MainActor` in this layer — views bind to models directly via `@Query`, and models are passed by reference into stores that mutate them.

- **`Todo`** — root entity: `title` (defaults to `""`, a valid placeholder state), optional `todoDescription`/`dueDate`, `isCompleted`, `order`, `createdAt`, and `reminderID`/`reminderListID` (nullable EventKit identifiers — `EKReminder.calendarItemIdentifier` / `EKCalendar.calendarIdentifier` — linking to the Reminders mirror; both nil ⇒ not yet synced). Owns its children via `@Relationship(deleteRule: .cascade) var subTodos: [SubTodo]`.
- **`SubTodo`** — child entity: `title`, `isCompleted`, `order`, `parent: Todo?` (auto-inferred inverse of `Todo.subTodos`). Deleting a `Todo` cascades to its `SubTodo`s via the rule on the parent side. **Not synced** to Reminders.
- **`Reorderable`** (`AnyObject` protocol) — requires `id: UUID { get }` + `order: Int { get set }`; both models conform via empty extensions. It deliberately does **not** inherit `Identifiable`: `@Model` synthesizes its own `Identifiable` keyed on `persistentModelID`, and combining the two reintroduces an ambiguous-`id` clash. So two identities coexist — SwiftData's `persistentModelID` vs the app's `id: UUID` (reorder/UI code keys on the UUID).

**Container & migration.** `todo_widgetApp` builds the container once at init (`sharedModelContainer = TodoModelContainerFactory.make()`, injected via `.modelContainer`). `TodoSchemaV1` is the only version (`models: [Todo, SubTodo]`); `TodoMigrationPlan.stages` is empty. To evolve: add a `TodoSchemaV2`, append to `schemas`, and add a real `MigrationStage`.

> **Footgun — destructive container fallback.** `TodoModelContainerFactory.make()` wraps its first attempt in `try?`, swallowing **every** error (not just migration failures). On any failure it silently `FileManager.removeItem(at:)` (total data wipe) and retries — and the retry **drops the `migrationPlan:` argument**. So a buggy/incompatible migration silently nukes the store rather than surfacing an error. This is last-resort corruption recovery only; never lean on it to "handle" a migration — add a proper `MigrationStage`. (Note: this fallback lives in `TodoModelContainerFactory`, not inline in `todo_widgetApp`.)

### View stores (`Stores/`)

A per-view, unidirectional **State + Intent** presentation layer between models and views. (This supersedes any older "no ViewModel layer" note — there *is* one now, but it holds **UI state only**; `Todo`/`SubTodo`/`ModelContext` are passed in per intent, so models still bind directly to views.)

Every store has the same shape:

```swift
@MainActor @Observable final class XStore {
    struct State { /* mutable UI state */ }
    enum Intent { /* every action the view can fire */ }
    var state = State()
    func send(_ intent: Intent) { switch intent { ... } }
}
```

- **Ownership**: each view owns its store with `@State private var store = XStore()` (the Observation idiom — **not** `@StateObject`/`@ObservedObject`). Views read `store.state.x` and act via `store.send(.intent(...))`. Even two-way bindings route writes through `send`: `Binding(get: { store.state.x }, set: { store.send(.updateX($0)) })`. `EditTodoFormStore` is special-cased (`_store = State(initialValue: EditTodoFormStore(todo:))`) because it seeds drafts from the model.
- **Side-effect routing**: stores are the only callers of `RemindersSync.shared`, `CalendarService.shared`, and `WidgetWindowChannel.shared` — views never touch those singletons. List-mutating writes are wrapped in `withAnimation(DesignTokens.toggleSpring / layoutSpring)` **inside** `send`, not in the view.

The six stores: `TodoListStore` (shell — edit mode, drag transients, scroll-edge flags, reminders banner strings; the **single** owner of `WidgetWindowChannel`), `TodoRowStore` (per-row `MoreMenuContent` popover enum, sub-todo entry, list picker, and the completion countdown via an `@ObservationIgnored countdownTask`), `SubTodoRowStore` (child actions/edit; purely local mutation), `EditTodoFormStore` (`init(todo:)`, `isNew` captured once as `todo.title.isEmpty`, title/desc are drafts committed on `.save`), `HeaderStore` (widget-title editing; reads `widgetTitle` from an injectable `UserDefaults` in `init` but `.commitTitle` writes to `UserDefaults.standard` hardcoded), `CalendarStore` (displayed month + selected date only — all event data lives in `CalendarService`).

### Reminders sync (`Services/Reminders*`)

Two-way mirror between local `Todo` and macOS Reminders `EKReminder`, decomposed into a facade + collaborators. Uniformly `@MainActor`.

- **`RemindersSync.shared`** (`@MainActor @Observable`) is the only app-facing object. It owns the `RemindersEventStore` wrapper, a stateless `RemindersReconciler`, a weak `ModelContext`, the `.EKEventStoreChanged` observer, the `isApplyingRemoteChange` guard, and the UI `status`. API: `start(with:)`, `refresh()`, `requestAccessFromUser()`, `push(_:)`, `delete(reminderID:)`, `move(_:toListID:)`, plus list helpers (`availableLists`, `createList`, `color(forListID:)`).
- **`RemindersEventStore`** is the *sole* holder of `EKEventStore`. All EventKit reads/writes go through it: auth, the `"todo widget"` default calendar, list enumeration/creation/color, `fetchAllReminders()`, `save(_:)` (the push write), `delete`, `recreateStore()`.
- **`RemindersReconciler`** is a stateless `@MainActor struct`. `reconcile(...)` merges a fetched `[EKReminder]` snapshot into a `ModelContext` and **never touches EventKit** — it gets a `pushUnsyncedTodo` callback for the one write it needs. Keep this seam.
- Leaves: `RemindersDateMapper` (Date ↔ `DateComponents`), `RemindersTypes` (`ReminderList`, `RemindersSyncStatus`), `RemindersLogger` (`remindersLog`, subsystem `todo-widget` / category `RemindersSync`).

**Bootstrap / pull.** `start(with:)` → resolve access → on grant: `ensureDefaultCalendar()`, install observer, `pullAndReconcile()`. The observer re-runs `pullAndReconcile` on every `.EKEventStoreChanged`. `fetchAllReminders()` does `store.reset()` then a predicate over **all** lists; `pullAndReconcile` sets `isApplyingRemoteChange = true` (defer-reset) around the reconcile.

**Push vs. pull guard.** `isApplyingRemoteChange` is true only during `pullAndReconcile`. The public `push(_:)` (check/uncheck, edit save, list move) early-returns while the guard is up, breaking push↔pull loops. The reconciler's `pushUnsyncedTodo` callback bypasses this with `skipGuard:true`, so local-only todos get pushed *from inside* reconcile. Empty-title todos are never pushed.

**Permission + recreate-store fix.** `resolveAccess(requestIfNeeded:)` maps `EKAuthorizationStatus` and sets **both** `status` (drives the banner) and `eventStore.hasAccess` (gates every operation) in tandem — they live in different objects, so keep them synced. On a `notDetermined→granted` transition, `requestAccess()` calls `resetEventStoreAfterPermissionChange()` → removes the observer + `eventStore.recreateStore()` (new `EKEventStore`, nil default calendar); bootstrap then re-runs `ensureDefaultCalendar()` and re-installs the observer. `EKEventStore` caches auth state at construction — skip the rebuild and fetch/save silently no-op after a grant.

> **Code currently contradicts older docs:** (1) **Import is not list-scoped** — `fetchAllReminders` uses `predicateForReminders(in: nil)` and import filters only `!isCompleted && allowsContentModifications && not-already-mapped`, so new incomplete reminders are imported from **any writable list**, not just `"todo widget"`. (2) **No remote-delete prune** — `reconcile` never deletes local todos when their `reminderID` vanishes remotely; there is no prune path at all (the previously-dead `pruneMissingRemoteItems` param + `deleteLocallyRemovedRemoteItems` seam was removed). (3) `RemindersDateMapper` treats exactly midnight as a date-only due date and drops the time.

### Calendar services (`Services/Calendar*`)

An EventKit `.event` read+write layer that mirrors the Reminders stack but is **not** SwiftData-backed — events live only in macOS Calendar and reach views as immutable `CalendarEvent` snapshots. `.event` access is a **distinct permission** from Reminders (second OS prompt).

- **`CalendarService.shared`** (`@MainActor @Observable`) — facade + cache, parallel to `RemindersSync`. Owns a `CalendarEventStore`, the published `events: [CalendarEvent]` + `status`, and a fetch **window** (`loadedStart`/`loadedEnd`/`anchorMonth`). Lifecycle: `start(month:)` / `requestAccessFromUser(month:)` / `setMonth(_:)` / `refresh()`. `setMonth` records `anchorMonth` always but only reloads when granted; `refresh()` no-ops unless `anchorMonth` is set and no request is in flight.
- **Fetch window (`reloadWindow(around:)`)** — one in-memory array feeds both grid dots and the agenda. Range is asymmetric: `monthStart − 7d` … `(monthStart + 1 month) + agendaHorizonDays(90) + 7d`. Query helpers read this cache: `events(on:)`, `upcomingEvents(from:days:)`, `eventColors(forDay:)` (dedup, ≤3).
- **`CalendarEventStore`** (`@MainActor`) — raw `EKEventStore(.event)` wrapper. Uses `requestFullAccessToEvents` (write-only access treated as not usable). Gates reads/writes on its own `hasAccess` bool (set via `markAccessGranted/Denied`), not on `EKAuthorizationStatus` at call time. **Must** `recreateStore()` after notDetermined→granted (same caching footgun as Reminders).
- **Agent-callable mutation API** — `CalendarService.createEvent / update / delete` take only raw values (`String`/`Date`/`Bool`, `calendarID: String?`), never view types or `EKEvent`. This is the seam the future "message → event" Claude agent calls directly. Every mutation reloads the window. Saves use `span: .thisEvent` (single occurrence); `resolvedCalendar` falls back generously (requested writable ID → default-for-new-events → first writable); `apply` clamps `endDate = max(end, start)`.
- **`CalendarMath`** — pure `Calendar` extension: `startOfMonth(for:)`, `monthGridDays(for:)` (6-week / 42-cell grid honoring `firstWeekday`), `orderedWeekdaySymbols(locale:)`.
- **`CalendarTypes`** — `CalendarEvent` (`id = "eventID@startTime"` so recurring occurrences, which share one `eventIdentifier`, stay unique), `WritableCalendar` (picker), `CalendarAccessStatus` (isomorphic to `RemindersSyncStatus`, reuses `RemindersPermissionBanner`). The `AccessResolution` enum is **shared** from `RemindersSync+Access.swift`. Logs to category `CalendarService`.

### Window / AppKit layer (`Window/`)

The window is **manually driven**, not SwiftUI-resized. `AppDelegate` is a thin coordinator delegating to three focused controllers:

- **`WidgetWindowController`** (`@MainActor`, `NSWindowDelegate`) — owns all window lifecycle/sizing/presentation. `attach()` (run inside `DispatchQueue.main.async` from `applicationDidFinishLaunching`, since SwiftUI builds the `NSWindow` on the next runloop) grabs `NSApp.windows.first`, applies base config (`borderless`+`resizable`, clear/non-opaque, `.normal` level, `animationBehavior = .none`, collection behavior `[.moveToActiveSpace, .fullScreenAuxiliary]`, corner-radius mask), `object_setClass`-swaps it to `TopAnchoredWindow`, calls `enableTopAnchor()`, and keeps a **strong ref** to it. `applyContentHeight` sets the frame `animate:false`, capped at `widgetMaxHeight` (980).
- **`GlobalHotkeyController`** (`@MainActor`) — wraps a `HotKey` (SPM) for **⌃+1** → `toggleVisibility()`. AppDelegate must retain it or the hotkey unregisters.
- **`MainMenuBuilder`** — installs `NSApp.mainMenu` (⌘Q terminate + Edit menu). Under LSUIElement the menu bar is hidden but key equivalents still require a `mainMenu`.

**LSUIElement.** `applicationShouldTerminateAfterLastWindowClosed` → `false`; `windowShouldClose` calls `orderOut` and returns `false` — the X button hides the widget, never destroys it; quit is ⌘Q. `applicationDidBecomeActive` / `applicationShouldHandleReopen` call `restorePresentation()`; `didBecomeActive` also refreshes `RemindersSync` and `CalendarService`.

**Event channel.** `WidgetWindowChannel.shared` (`@MainActor` singleton, type-safe single-consumer) **replaced** the old two `Notification.Name` posts for height/edit-mode. Flow: `TodoListView.onGeometryChange` → `store.send(.widgetHeightChanged)` → `TodoListStore` → `WidgetWindowChannel.reportContentHeight(_:)`; edit-mode via `reportEditModeChanged(_:)`. AppDelegate is the **sole** consumer (installs `onContentHeightChanged`/`onEditModeChanged`). Don't reintroduce `NotificationCenter` for these.

**`TopAnchoredWindow` anchoring (load-bearing).** Pins the window's **top-left corner** to an anchor (`anchorLeftX`, `anchorTopY = maxY`). Three frame paths behave differently:

1. **Programmatic resize** (content-height change) — `setFrame`/`setContentSize` run through `adjusted()` → `resizedFrame(forSize:)`, which discards the proposed origin and rebuilds top-left as `(anchorLeftX, anchorTopY − height)` with **no screen clamp**. The source intent of omitting the vertical clamp here is to keep the top edge fixed across content-height changes (a vertical clamp would couple top position to height).
2. **Non-drag system reposition** — `setFrameOrigin`/`setFrameTopLeftPoint` while `!userIsDragging`: the move is rejected and snapped back via `anchoredFrame(forSize:)`, which **does** `clampedToScreen` (recovers a window pushed off-screen by Spaces/display changes).
3. **User drag** — `userIsDragging` is a live read of `NSEvent.pressedMouseButtons & 0x1` (stateless, no stuck-flag failure mode). The move is accepted and the anchor is **updated**.

Both `setFrame` overrides force `animate:false` (AppKit's interpolation animates from bottom-left, bypassing the origin override and jittering the top edge). `applyFrame` wraps `super` with `isProgrammaticFrameChange = true` (defer-reset) so the overrides — guarded by `anchorEnabled && !isProgrammaticFrameChange` — don't re-trigger internally.

> **Open issue (do not assume solved):** switching tabs (calendar↔reminders, different heights) still visibly **moves the window's position**. Removing the resize-path vertical clamp did **not** resolve it, so the cause is elsewhere — re-investigate from scratch rather than trusting that the resize path is correct. The previous doc's confident "top edge fixed" claim sent debugging down the wrong path; keep this descriptive.

> **`object_setClass` constraint:** all `TopAnchoredWindow` state (`anchorEnabled`, `anchorTopY`, `anchorLeftX`, `isProgrammaticFrameChange`) is stored as **ObjC associated objects**, never Swift stored properties — the class is swapped onto an existing `NSWindow` whose memory layout has no slots for them, so stored properties there are UB. The frame overrides also emit `OSLog .notice` lines (category `Window`) on every change — debug instrumentation left in.

### Reminders/Todo view layer (`Views/`, non-calendar)

`TodoListView` is the **shell/root**. It owns the *single* window-height reporter (`.onGeometryChange → store.send(.widgetHeightChanged)`), the glass card, the fixed width, the `WidgetTab` switch, and the permission banner. Tab content swaps inside the measured subtree. The scrollable list is a `ScrollViewReader` with `Color.clear` top/bottom anchors, auto-scroll-to-bottom on `todos.count` increase, and `ScrollEdgeIndicator` fades/chevrons driven by `onScrollGeometryChange`; height is capped via `.fixedSize(vertical:) + .frame(maxHeight: maxListHeight)`.

- **Drag-to-reorder** (`ReorderDropDelegate` + `.reorderableRow` modifier, both generic over `Reorderable`): gated on `isEditMode` at every entry point. **Order is reassigned only in `performDrop`** — mid-drag shows just the blue `dropTargetID` highlight. `canReorder` gates per model (Todos: any; SubTodos: same `parent`). `ReorderDropResetDelegate` on the container clears state on dead-space drops.
- **`TodoRowView` single-popover pattern:** one `.popover` bound to `moreMenu != .closed`, content swapped via `TodoRowStore.MoreMenuContent` (`.actions`/`.editForm`/`.createList`). Closing `.editForm` with an empty title deletes the todo (local + remote). **Do not** add a second sibling popover on this anchor (unreliable on macOS).
- **`SubTodoRowView` deliberately differs:** it uses *two* sibling popovers (actions → edit) chained through `DesignTokens.popoverChainDelay`. Don't "unify" it with the single-popover rule — the delay exists because macOS can't dismiss-and-present at one anchor in a single frame.
- **Completion countdown:** check → push → `TodoRowStore` runs a per-store `countdownTask` for `@AppStorage("completionDeleteDelay")` (default 5; ≤0 = immediate) then deletes locally + via `RemindersSync.delete`. `CountdownBadge` tap cancels.
- **Empty-title = placeholder:** `addTodo` inserts `title:""`; `autoOpenEditFormIfNeeded` opens the edit form after `rowAppearSettleDelay`; must never be pushed.
- **Dates** always go through the `@MainActor` `DateFormatters` cache (same-year/other-year templates) and `Locale.userPreferred` — never allocate a formatter per row. `TodoRowDisplayContent` measures its own height via a *local* `PreferenceKey` to size the reminder-color accent bar (independent of the window height reporter).
- **Reusable chrome:** `PopoverHeader`, `PopoverActionButton`, `RowActionsPopover`, `TodoActionsPopover` (adds `ReminderListPickerMenu` + `CreateReminderListPopover`). Visual primitives: `CheckboxView`, `CountdownBadge`, `ScrollEdgeIndicator`, `GlassCardBackground` (`.glassEffect` + `compositingGroup` shadow), `AppBackground` (defined but not currently applied).

### Calendar view layer + tabs (`Views/Calendar/`, `Views/WidgetTab.swift`)

Two tabs via `WidgetTab` (`.calendar` / `.reminders`), persisted as rawValue in `@AppStorage("selectedWidgetTab")` on the shell. `WidgetTabBar` is a Liquid-Glass segmented control: a `glassEffect` capsule track with a selected pill that slides via `matchedGeometryEffect(id: "pill")` animated with `toggleSpring`. The shell's `tabBinding` force-resets reminders edit mode when leaving `.reminders` (so window-background drag isn't stranded disabled).

- **Ownership / height:** the shell owns the **single** height reporter; `CalendarView` is *pure content* and must **never** add a second reporter (re-introduces window jitter). The shell passes `agendaMaxHeight = widgetMaxHeight − calendarChromeHeight`, where `calendarChromeHeight = 60 + tabBarHeight + 44 + 22 + 228 + 30` (shell + tab bar + month-nav + weekday row + 6×38 grid + agenda header). Resize the grid/nav ⇒ retune **`calendarChromeHeight`**, not the reminders `chromeHeight`.
- **Layout:** `CalendarView` = optional `RemindersPermissionBanner` → `monthNav` (chevrons, month title, conditional today-jump, `+` create-form popover) → `CalendarGridView` (**fixed**) → divider → agenda `ScrollView` capped at `agendaMaxHeight`. **The grid is fixed; only the agenda scrolls.**
- **`CalendarGridView`** — weekday header + 7-col `LazyVGrid` of 42 cells (`monthGridDays`), per-day dots from `service.eventColors(forDay:)`. **`CalendarDayCell`** — today = blue *ring*; selected = filled blue *disc* (white number); up to 3 calendar-color dots in a fixed 4pt row reserved even when empty (keeps cell heights equal).
- **Agenda** groups `upcomingEvents(from: selectedDate)` by `max(startOfDay(event.start), selectedDate)` — events that began before the selected day are clamped into the selected-day section (intentional "upcoming from selected day"). Each `CalendarEventRow` hosts its own edit popover.
- **State vs. data:** `CalendarStore` holds only `displayedMonth`/`selectedDate` + nav intents; every navigation intent fires `service.setMonth(...)` in a `Task` to reload the fetch window; `selectDay` re-homes `displayedMonth` for an other-month cell. All event data/persistence live in `CalendarService.shared`.
- **Forms:** `CalendarEventFormView` seeds local `@State` from its `Mode` (`.create(Date)`/`.edit(CalendarEvent)`) in `init` (no model binding) and commits through the raw-value `CalendarService` API. `startBinding` shifts `end` to preserve duration; `endBinding` clamps `end ≥ start`. New-event start = next top-of-hour today, else 09:00. `CalendarFormatters` caches time/section/month formatters with `.userPreferred` locale.

### Design system (`Style/Tokens.swift`)

The whole design system in one file. A `Color(light:dark:)` extension wraps `NSColor(dynamicProvider:)` so tokens auto-resolve per appearance; views never branch on `colorScheme`. Two layered enums:

- **`DT`** — raw source of truth: dynamic colors, sizes (`widgetWidth` 340, `widgetMaxHeight` 980, `cornerRadius` 24, `checkbox`/`subCheckbox`, `headerButton`, `subIndent`…), fonts, animations, and `headerButtonFill/Stroke/Highlight(active:hovered:)` helpers.
- **`DesignTokens`** — view-facing semantic alias namespace. **All view code references `DesignTokens`, never `DT`.** Add a token: define in `DT`, alias in `DesignTokens`. (Exceptions exist — `overdueColor`, `disabledOpacity` are defined inline in `DesignTokens` with no `DT` backing.)

Tuned animation values to preserve:
- `toggleSpring` (`response 0.3, damping 0.7`) — interactive transitions (checks, hover, popovers, drag highlight, tab pill).
- `layoutSpring` (`response 0.55, damping 0.95`) — list mutations (insert/delete/reorder commit).
- `rowAppearSettleDelay` (320 ms) — auto-edit-on-create delay, ~60% of `layoutSpring`'s response. **Retune it whenever `layoutSpring` changes.**
- `popoverChainDelay` (50 ms) — minimum gap to close popover A then open popover B at the same anchor.

## Key behaviors to preserve

- **One height reporter only.** The shell (`TodoListView`) owns `.onGeometryChange → WidgetWindowChannel.reportContentHeight`. Tab content (incl. `CalendarView`) is pure content inside the measured subtree — a second reporter makes the manually-driven window jitter.
- **Window resize rebuilds top-left from the anchor with NO clamp** (`resizedFrame`); only non-drag system repositions clamp to screen (`anchoredFrame`). (Note: tab-switching still moves the window — see the "Open issue" callout in the Window section; this path is *not* confirmed to be the fix.)
- **`TopAnchoredWindow` state must stay in associated objects** — never add Swift stored properties (the class is `object_setClass`-swapped).
- **`RemindersSync.isApplyingRemoteChange` must wrap any path that mutates local todos in response to a remote change**, or pull→push→pull loops.
- **Empty-title todos are placeholder state** — never pushed to Reminders; closing the edit form on one deletes it (locally, and remotely if it had a `reminderID`).
- **`MoreMenuContent` single-popover pattern in `TodoRowView`** — no second sibling `.popover` on the same anchor; swap content via the enum.
- **Sub-todos cap at 20 per `Todo`** (add button hidden at the cap) and are **not** synced.
- **Drag-to-reorder is gated on edit mode; reorder commits only on `performDrop`**, never in `dropEntered`/`dropUpdated`.
- **Stores hold UI state only** (State+Intent+`send`, `@State`-owned); models/`ModelContext` are passed in per intent, and all singleton side effects go through `send`.
- **Use `toggleSpring` for interactive animation and `layoutSpring` for list mutations** — mixing them produces a "row fades fast, neighbors catch up late" mismatch.
- **`CalendarService.createEvent/update/delete` are the agent-facing API** — keep them callable with raw values (no view/EventKit types).
- **Calendar grid is fixed; only the agenda scrolls** — cap it with `calendarChromeHeight`, not the reminders `chromeHeight`.
- **`recreateStore()` is mandatory after a notDetermined→granted transition** for both `RemindersEventStore` and `CalendarEventStore` — `EKEventStore` caches auth at construction; skip it and fetch/save silently return empty.
- **Schema changes add a new `VersionedSchema` + `MigrationStage`.** The `TodoModelContainerFactory` store-delete is destructive last-resort recovery that triggers on *any* open failure — never rely on it.
- **`@AppStorage("completionDeleteDelay")` is the source of truth** for auto-delete timing; never hardcode.

## Localization

UI strings are **Korean** (hardcoded); the app ships **no `.lproj`** localizations. Date handling keys off `Locale.userPreferred` (= `Locale(identifier: Locale.preferredLanguages.first…)`, **not** `Locale.current`), which is also injected into `DatePicker`s via `.environment(\.locale, .userPreferred)` (there is no longer any forced `ja_JP`). All user-facing dates go through the cached `DateFormatters` (reminders) / `CalendarFormatters` (calendar) — never allocate per row. A few inline language forks remain (e.g. "오늘"/"Today", " 지남"/" overdue" in `TodoDueDateDisplay`). There is no settings UI for locale.
