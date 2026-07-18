// Created by Eric Savoie on 7/16/26.
// Copyright © 2026 Eric Savoie. All rights reserved.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest

@testable import HorizonCalendar

final class WeekDataTests: XCTestCase {

  func testSundayFirstWeekCrossesMonthBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1

    let content = CalendarViewContent(
      calendar: calendar,
      visibleDateRange: date(
        2026, 5, 1, calendar: calendar)...date(2026, 6, 30, calendar: calendar),
      monthsLayout: .horizontal
    )
    let weekData = WeekData(content: content)
    let index = weekData.weekIndex(
      containing: calendar.day(containing: date(2026, 6, 2, calendar: calendar)))
    let days = weekData.days(inWeekAt: index).compactMap { $0 }

    XCTAssertEqual(days.count, 7)
    XCTAssertEqual(days.first, calendar.day(containing: date(2026, 5, 31, calendar: calendar)))
    XCTAssertEqual(days.last, calendar.day(containing: date(2026, 6, 6, calendar: calendar)))
  }

  func testMondayFirstWeekCrossesYearBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2

    let content = CalendarViewContent(
      calendar: calendar,
      visibleDateRange: date(
        2025, 12, 1, calendar: calendar)...date(2026, 1, 31, calendar: calendar),
      monthsLayout: .horizontal
    )
    let weekData = WeekData(content: content)
    let index = weekData.weekIndex(
      containing: calendar.day(containing: date(2026, 1, 1, calendar: calendar)))
    let days = weekData.days(inWeekAt: index).compactMap { $0 }

    XCTAssertEqual(days.count, 7)
    XCTAssertEqual(days.first, calendar.day(containing: date(2025, 12, 29, calendar: calendar)))
    XCTAssertEqual(days.last, calendar.day(containing: date(2026, 1, 4, calendar: calendar)))
  }

  func testBoundaryWeekOmitsDaysOutsideVisibleRange() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2

    let content = CalendarViewContent(
      calendar: calendar,
      visibleDateRange: date(
        2026, 7, 16, calendar: calendar)...date(2026, 7, 20, calendar: calendar),
      monthsLayout: .vertical(
        options: .init(alwaysShowCompleteBoundaryMonths: false)
      )
    )
    let weekData = WeekData(content: content)

    XCTAssertEqual(weekData.weekCount, 2)
    XCTAssertEqual(weekData.days(inWeekAt: 0).compactMap { $0 }.count, 4)
    XCTAssertEqual(weekData.days(inWeekAt: 1).compactMap { $0 }.count, 1)
  }

  func testWeekIndexIsClampedToAvailableWeeks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let content = CalendarViewContent(
      calendar: calendar,
      visibleDateRange: date(
        2026, 1, 1, calendar: calendar)...date(2026, 1, 31, calendar: calendar),
      monthsLayout: .horizontal
    )
    let weekData = WeekData(content: content)

    XCTAssertEqual(
      weekData.weekIndex(
        containing: calendar.day(containing: date(2025, 1, 1, calendar: calendar))),
      0
    )
    XCTAssertEqual(
      weekData.weekIndex(
        containing: calendar.day(containing: date(2027, 1, 1, calendar: calendar))),
      weekData.weekCount - 1
    )
  }

  func testHorizontalWeekLayoutMatchesCenteredMonthPageGeometry() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let content = CalendarViewContent(
      calendar: calendar,
      visibleDateRange: date(
        2026, 1, 1, calendar: calendar)...date(2026, 12, 31, calendar: calendar),
      monthsLayout: .horizontal
    )
    .interMonthSpacing(18)
    .horizontalDayMargin(4)

    let metrics = WeekLayoutMetrics(
      content: content,
      width: 408,
      layoutMargins: .zero
    )

    XCTAssertEqual(metrics.monthFrame.minX, 9, accuracy: 0.001)
    XCTAssertEqual(metrics.monthFrame.width, 390, accuracy: 0.001)
    XCTAssertEqual(metrics.collectionViewFrame.minX, 9, accuracy: 0.001)
    XCTAssertEqual(metrics.collectionViewFrame.width, 390, accuracy: 0.001)
    XCTAssertEqual(metrics.dayWidth, 52.285_714, accuracy: 0.001)
    XCTAssertEqual(metrics.frameForDay(at: 5).minX, 290.428_571, accuracy: 0.001)
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }
}
