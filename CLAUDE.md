# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Pure Xcode project. No package manager, no build scripts.

- **Build**: `Cmd+B` in Xcode, or `xcodebuild -project "todo widget.xcodeproj" -scheme "todo widget" build`
- **Run**: `Cmd+R` in Xcode
- **Tests**: `Cmd+U` in Xcode, or `xcodebuild test -project "todo widget.xcodeproj" -scheme "todo widget"`
- Single test: `xcodebuild test -project "todo widget.xcodeproj" -scheme "todo widget" -only-testing:"todo widgetTests/<TestClass>/<testMethod>"`

There is also an `AGENTS.md` (the Codex equivalent of this file). Keep the architecture description in `AGENTS.md` in sync with edits here.

## Architecture

macOS SwiftUI app that renders as a floating widget with optional always-on-top via global hotkey. No ViewModel layer — SwiftData models bind directly to views, and `RemindersSync.shared` is the only stateful service.

### Data layer (`Models/`)
- `Todo` — title, optional description, optional `dueDate`, completion, `order`, `createdAt`. Owns `[SubTodo]` via `@Relationship(deleteRule: .cascade)`. `reminderID` (EKReminder `calendarItemIdentifier`) and `reminderListID` (EKCalendar `calendarIdentifier`) wire each todo to its mirror in macOS Reminders. Both nil = not yet synced.
- `SubTodo` — title, completion, `order`, `parent: Todo?` back-reference. **Not synced** to Reminders (the EventKit API doesn't expose sub-tasks reliably).
- `Reorderable` protocol — `id: UUID` + `var order: Int { get set }`. Both models conform. The protocol declares `id` as a raw requirement (not via `Identifiable`) to avoid clashing with the `Identifiable` synthesized by `@Model` over `PersistentIdentifier`.
- `TodoSchema.swift` — `TodoSchemaV1: VersionedSchema` + `TodoMigrationPlan: SchemaMigrationPlan`. Schema bumps go through this plan. The app falls back to deleting the store only if the migration plan itself fails — destructive, so add a real `MigrationStage` rather than relying on it.

### Reminders sync (`Services/RemindersSync.swift`)
`RemindersSync.shared` is a `@MainActor @Observable` singleton that owns an `EKEventStore` and bridges local `Todo` ↔ `EKReminder` two-way:

- **Bootstrap** (`start(with:)` from `TodoListView.task`, also re-run on `applicationDidBecomeActive`): checks/requests Reminders permission, ensures a default calendar named **"todo widget"** exists, registers an `.EKEventStoreChanged` observer, then runs a `pullAndReconcile`. The bootstrap is idempotent — re-running is safe.
- **Pull**: deletes local todos whose `reminderID` no longer exists across any list, applies remote field changes (title/notes/due/completed/list) to matched todos, imports new reminders **only** from the default "todo widget" list, and pushes any local todos that don't yet have a `reminderID`.
- **Push** (`push(_:)` from check/uncheck, edit-form save, list move, and bootstrap): saves the `EKReminder`, recording back `reminderID`/`reminderListID`. Skipped while `isApplyingRemoteChange` is true (set during `pullAndReconcile`) to break push↔pull loops; `skipGuard:true` is the bootstrap escape hatch. Empty-title todos are skipped (placeholder rows).
- **Permission UI**: `status` (`.unknown` / `.notDetermined` / `.denied` / `.granted`) drives a banner under the header in `TodoListView` that links to `x-apple.systempreferences:...Privacy_Reminders`.
- **`recreateStoreIfNeeded`** — `EKEventStore` caches its permission state at construction. After a notDetermined→granted transition we throw the store away and rebuild, otherwise fetch/save can silently no-op.
- Logs to subsystem `todo-widget`, category `RemindersSync` (filter in Console.app).

### View layer (`Views/`)
- `TodoListView` — root. `@Query`-sorted todo list, edit-mode toggle, drag-to-reorder, scroll affordances (top/bottom fade + chevron with `scrollTo`), and the permission banner. Posts widget intrinsic height to `AppDelegate` via `Notification.Name.widgetContentHeightChanged` (see Window behavior).
- `TodoRowView` — per-item row. Drives:
  - **Completion countdown** — on check, counts down `@AppStorage("completionDeleteDelay")` seconds (default 5) then deletes locally and via `RemindersSync.delete`. Cancel by tapping `CountdownBadge`.
  - **Auto-edit-on-create** — empty-title todos pop the edit form after `DesignTokens.rowAppearSettleDelay`. Closing the form with a still-empty title deletes the todo.
  - **`...` menu** — single popover whose content swaps via a `MoreMenuContent` enum (`.actions` / `.editForm` / `.closed`). Two `.popover` modifiers on the same anchor are unreliable on macOS — keep this single-popover/state-swap pattern.
  - **Date display** — `dateDisplayInfo()` encodes due state in color/weight: today = blue emphasized, overdue = red emphasized, future/none = neutral.
- `SubTodoRowView` — child row with its own checkbox + `...` actions popover (edit/delete). Uses `popoverChainDelay` to chain action-popover-close → edit-popover-open.
- `EditTodoFormView` — title / description / date / time. Locale is forced to `ja_JP` on the date picker to get a stable `yyyy/MM/dd` slash format regardless of system locale.
- `HeaderView` — widget title (double-click or pencil button to edit, persisted to `@AppStorage("widgetTitle")`) + add and edit-mode toggle buttons.
- **Reorder primitives**:
  - `ReorderDropDelegate<Item: Reorderable>` — drop-target delegate. Tracks a `dropTargetID` for the blue highlight and commits the actual `order` reassignment only on `performDrop` (so rows don't shuffle mid-drag).
  - `ReorderDropResetDelegate<Item>` — fallback delegate attached to the container; resets `dragging`/`dropTargetID` if a drop ends in dead space.
  - `.reorderableRow(item:siblings:isEditMode:canReorder:dragging:dropTargetID:dragPreview:)` view modifier (in `ReorderableRow.swift`) — bundles drop-highlight bg, opacity/scale-while-dragging, `.onDrag`, and `ReorderDropDelegate` attachment. Used by both Todo and SubTodo rows; the per-model "can drag here?" rule is the `canReorder` closure (SubTodos must share a parent; Todos accept any).
- **Popover primitives** — `PopoverHeader` (title + optional X) and `RowActionsPopover` (edit/delete) deduplicate the popover chrome shared by Todo and SubTodo. `TodoActionsPopover` adds a Reminder list picker (color circle + Menu) on top.
- `DateFormatters` — `@MainActor` cache of four `DateFormatter`s (ko/en × current-year/other-year). Always go through `DateFormatters.formatter(isKo:sameYear:)`; do not allocate fresh formatters per row.
- `CheckboxView`, `CountdownBadge`, `GlassCardBackground`, `AppBackground` — visual primitives.

### Design system (`Style/Tokens.swift`)
Two enums:
- `DT` — raw light/dark dynamic values (`Color(light:dark:)`), sizes, fonts, animations. The `headerButton*(active:hovered:)` helpers live here too.
- `DesignTokens` — view-facing semantic alias namespace. **All view code should reference `DesignTokens`, not `DT`.**
Adding a token: define the raw value in `DT`, then add a semantic alias in `DesignTokens`.

Tuned animation values to be aware of:
- `toggleSpring` — every interactive transition (checks, hover, popovers, drag highlight). Use this for consistency.
- `layoutSpring` — list-level moves (insert/delete/reorder commit).
- `rowAppearSettleDelay` (320 ms) — auto-edit-on-create delay; targets ~60% of `layoutSpring`. If you change `layoutSpring`, retune this.
- `popoverChainDelay` (50 ms) — minimum gap before opening popover B at the same anchor where popover A just closed.

### Window behavior (`todo_widgetApp.swift`)
The window is **manually driven**, not SwiftUI-resized. Two coordinated pieces:

1. **`TopAnchoredWindow: NSWindow`** — overrides every `setFrame`/`setContentSize`/`setFrameOrigin` path so size changes keep the window's **top edge** fixed and grow/shrink downward. State (`anchorEnabled`, `anchorTopY`) is stored as Objective-C associated objects, **not** Swift stored properties — `object_setClass` swaps the class onto an existing `NSWindow` whose memory layout doesn't include those properties; stored properties there would be UB.

2. **Height-driven layout** — `TodoListView` measures its intrinsic height with `GeometryReader` and posts `Notification.Name.widgetContentHeightChanged`. `AppDelegate.applyContentHeight` caps it at `DesignTokens.widgetMaxHeight` (980) and applies the new frame with `animate:false`. We removed `.windowResizability(.contentSize)` because its internal animator interpolated each frame from bottom-left, producing visible top-edge jitter; SwiftUI animates the body content itself while the window snaps to the new size each frame.

`AppDelegate` is also responsible for:
- **LSUIElement pattern** — `windowShouldClose` orders the window out instead of closing, and `applicationShouldTerminateAfterLastWindowClosed` returns false. The app stays alive in the background; quit is `⌘Q` (installed via `installMainMenu`, since LSUIElement hides the menu bar but still honors key equivalents).
- **Global hotkey** `⌃+1` (via `HotKey` SPM dep) — toggles visibility, keeps the window at `.floating`, and activates app when summoning. The widget is not demoted when the app resigns active, so it stays visible above regular app windows and across Spaces.
- **Edit-mode drag conflict** — `Notification.Name.widgetEditModeChanged` toggles `isMovableByWindowBackground` so window-drag doesn't fight todo-reorder drag.
- **Reminders re-sync on activation** — `applicationDidBecomeActive` calls `RemindersSync.shared.refresh()` so a permission granted while the app was inactive is picked up next time the user focuses it.

### Localization
UI strings are Korean by default. A few inline forks (e.g. "오늘"/"Today", "지남"/"overdue") and the `DateFormatters` selection branch on `@AppStorage("appLocale")` (`ko` | `en`). There is no settings UI — toggle by writing to `UserDefaults`. Date pickers force `ja_JP` locale to get a slash-separated short format.

## Key behaviors to preserve
- **Drag-to-reorder is gated on edit mode.** Both `ReorderDropDelegate` and `reorderableRow` honor `isEditMode` — and `AppDelegate` disables window-background drag during edit mode to avoid conflicts.
- **Reorder commits on drop, not during.** Don't move it to `dropEntered`/`dropUpdated` — rows mid-drag should only show the blue highlight.
- **`@AppStorage("completionDeleteDelay")` is the source of truth** for auto-delete timing; do not hardcode.
- **Use `DesignTokens.toggleSpring` for interactive animations and `layoutSpring` for list mutations.** Mixing them produces a "row fades fast, neighbors catch up late" mismatch.
- **Sub-todos cap at 20 per `Todo`.** Enforced by hiding the add-sub button in `TodoRowView`.
- **Schema changes** add a new `VersionedSchema` + `MigrationStage`. The store-delete fallback in `todo_widgetApp.swift` is a last-resort recovery for true corruption.
- **`RemindersSync.isApplyingRemoteChange`** must wrap any code path that mutates local todos in response to a remote change, otherwise pull will trigger push will trigger pull.
- **Empty-title todos are placeholder state.** They must not be pushed to Reminders, and closing the edit form on one deletes it locally (and remotely, if it had been pushed).
- **`MoreMenuContent` single-popover pattern in `TodoRowView`** — do not add a second sibling `.popover` on the same anchor; swap content via the enum instead.
- **Window class swap (`object_setClass` to `TopAnchoredWindow`) requires associated-object storage.** Don't add Swift stored properties to `TopAnchoredWindow`.
