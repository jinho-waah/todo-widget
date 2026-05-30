//
//  todo_widgetTests.swift
//  todo widgetTests
//
//  Created by 진호 on 4/29/26.
//

import Foundation
import Testing
@testable import todo_widget

struct todo_widgetTests {

    @Test func reminderDueDateComponentsAreNilWhenDateIsMissing() {
        #expect(RemindersDateMapper.dueDateComponents(from: nil) == nil)
    }

    @Test func reminderDueDateComponentsOmitTimeWhenOnlyDateIsSet() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 6,
            hour: 0,
            minute: 0
        )))

        let components = try #require(RemindersDateMapper.dueDateComponents(from: date))

        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 6)
        #expect(components.hour == nil)
        #expect(components.minute == nil)
    }

    @Test func reminderDueDateComponentsIncludeTimeWhenTimeIsSet() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 6,
            hour: 14,
            minute: 30
        )))

        let components = try #require(RemindersDateMapper.dueDateComponents(from: date))

        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 6)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

}
