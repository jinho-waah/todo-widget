# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Run

This is a pure Xcode project with no package manager or build scripts.

- **Build**: `Cmd+B` in Xcode, or `xcodebuild -project "todo widget.xcodeproj" -scheme "todo widget" build`
- **Run**: `Cmd+R` in Xcode
- **Tests**: `Cmd+U` in Xcode, or `xcodebuild test -project "todo widget.xcodeproj" -scheme "todo widget"`

## Architecture

macOS SwiftUI app that renders as a floating, always-on-top widget. No ViewModel layer — SwiftData models bind directly to views.

### Data layer (`Models/`)
- `Todo` — main item with optional description, due date, completion state, and ordering index. Owns `SubTodo` via `@Relationship(deleteRule: .cascade)`.
- `SubTodo` — lightweight child item with title and completion state. Has a `parent: Todo?` back-reference.
- `TodoSchema.swift` — `TodoSchemaV1` (`VersionedSchema`) + `TodoMigrationPlan` (`SchemaMigrationPlan`). Adding a schema version: define `TodoSchemaV2`, append to `schemas`, add a `MigrationStage`. The app prefers the migration plan path; only on a genuine migration failure does it fall back to deleting the store.

### View layer (`Views/`)
- `TodoListView` — root view. Drives the `@Query`-sorted list, edit mode state, and drag-to-reorder via the generic `ReorderDropDelegate`.
- `TodoRowView` — per-item row. Manages completion countdown: on check, a `Task` counts down (`@AppStorage("completionDeleteDelay")` seconds, default 5) then deletes the todo. User can cancel via `CountdownBadge`. New todos with empty titles auto-open the edit form after `DesignTokens.rowAppearSettleDelay`; closing without a title deletes them. Date display color encodes due-date state: today = blue/emphasized, overdue = red, future/none = neutral gray (see `dateDisplayInfo()`).
- `EditTodoFormView` — Todo edit popover (title / description / date / time).
- `CountdownBadge` — circular progress badge shown during the post-completion auto-delete countdown.
- `ReorderDropDelegate<Item>` / `ReorderDropResetDelegate<Item>` — generic drag-reorder delegates shared by Todo and SubTodo. The per-model "can drag here?" rule (e.g. SubTodo only reorders within the same parent) is passed in via the `canReorder` closure.
- `HeaderView` — title + add/edit-mode toggle buttons.
- `SubTodoRowView` — child item row with its own checkbox.
- `CheckboxView`, `GlassCardBackground`, `AppBackground` — small shared visual primitives.

### Tabs + Calendar (`Views/WidgetTab.swift`, `Views/Calendar/`, `Services/Calendar*.swift`)
The widget has two tabs — **캘린더 (calendar)** and **미리 알림 (reminders)** — persisted via `@AppStorage("selectedWidgetTab")` in `TodoListView` (the shell). `WidgetTabBar` is a Liquid-Glass segmented control. The shell owns the single window-height reporter, glass card, and width; only the tab content swaps inside it (do **not** add a second height reporter in `CalendarView`).

The calendar is an itsycal-style **read+write** view over macOS Calendar (EventKit `.event` — a separate permission from Reminders). Events are not SwiftData-backed; they're value-type snapshots (`CalendarEvent`). `CalendarService.shared` (`@MainActor @Observable`) is the facade paralleling `RemindersSync`: it caches a fetch window around the displayed month, observes `.EKEventStoreChanged`, and exposes `createEvent/update/delete` as the entry points a future Claude "message → event" agent will call. `CalendarEventStore` mirrors `RemindersEventStore`, including the `recreateStore()`-after-permission-grant fix and `requestFullAccessToEvents`. `CalendarView` lays out month-nav → fixed grid (`CalendarGridView`/`CalendarDayCell`) → divider → a capped agenda `ScrollView` of `CalendarEventRow`s; `CalendarEventFormView` handles create/edit. `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` is set in both build configs.

### Design system (`Style/Tokens.swift`)
Two enums live here. `DT` holds raw light/dark dynamic values (colors, sizes, fonts, animations). `DesignTokens` is the view-facing alias namespace and is what every view should use. New tokens go in both: `DT` for the raw value, `DesignTokens` for the semantic name view code consumes.

### Window behavior (`todo_widgetApp.swift`)
`AppDelegate.configureWindow()` sets the window as borderless, floating level (`.floating`), transparent, joined to all spaces, and full-screen-auxiliary. Default size is 340×540 with `.windowResizability(.contentSize)` — height tracks content. The app terminates when its window is closed.

### Localization
UI strings are Korean by default. Date formatting (and a few inline strings like "Today"/"오늘", "overdue"/"지남") branches on `@AppStorage("appLocale")` (`ko` | `en`). There's no settings screen — toggling is via UserDefaults.

## Key behaviors to preserve
- Drag-to-reorder is **only active in edit mode** — `ReorderDropDelegate` enforces this via its `isEditMode` parameter.
- Countdown auto-delete uses `@AppStorage("completionDeleteDelay")` so it's user-configurable without a settings UI change.
- `DesignTokens.toggleSpring` is used for all interactive animations — don't use other animation curves for consistency.
- Sub-todos are capped at 20 per `Todo` (the add-sub button hides past that threshold in `TodoRowView`).
- Schema changes should add a new `VersionedSchema` and a migration stage in `TodoSchema.swift`, not rely on the destructive store-delete fallback.
