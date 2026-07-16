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

import UIKit

/// A calendar view that transitions between complete-month and single-week scopes.
///
/// `CalendarScopeView` preserves HorizonCalendar's existing month renderer and uses the same
/// `CalendarViewContent` providers for its paged week renderer. Custom day views, day backgrounds,
/// day ranges, layout metrics, calendar systems, and accessibility content therefore carry across
/// both scopes.
public final class CalendarScopeView: UIView, UIGestureRecognizerDelegate {

  // MARK: Lifecycle

  /// Creates a scoped calendar.
  ///
  /// - Parameters:
  ///   - initialContent: The content used to render both scopes.
  ///   - initialScope: The initially visible scope.
  ///   - initialDate: The date used to select the initially visible month or week.
  public init(
    initialContent: CalendarViewContent,
    initialScope: CalendarViewScope = .month,
    initialDate: Date = Date()
  ) {
    content = initialContent
    scope = initialScope
    anchorDate = initialDate
    monthCalendarView = CalendarView(initialContent: initialContent)
    weekCalendarView = WeekCalendarView(initialContent: initialContent)

    super.init(frame: .zero)

    clipsToBounds = true
    addSubview(monthCalendarView)
    addSubview(weekCalendarView)

    monthCalendarView.daySelectionHandler = { [weak self] day in
      self?.handleDaySelection(day)
    }
    weekCalendarView.daySelectionHandler = { [weak self] day in
      self?.handleDaySelection(day)
    }
    installScrollHandlers()

    scopePanGestureRecognizer.addTarget(self, action: #selector(handleScopePan(_:)))
    scopePanGestureRecognizer.delegate = self
    addGestureRecognizer(scopePanGestureRecognizer)

    configureVisibility(for: initialScope)
    scroll(toDayContaining: initialDate, scrollPosition: .centered, animated: false)
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Public

  /// The currently visible scope.
  public private(set) var scope: CalendarViewScope

  /// Called when a day is selected in either scope.
  public var daySelectionHandler: ((DayComponents) -> Void)?

  /// Called while the visible month or week scrolls.
  public var didScroll: ((_ visibleDayRange: DayComponentsRange, _ isUserDragging: Bool) -> Void)?

  /// Called when dragging the visible month or week ends.
  public var didEndDragging:
    (
      (
        _ visibleDayRange: DayComponentsRange,
        _ willDecelerate: Bool
      ) -> Void
    )?

  /// Called when the visible month or week finishes decelerating.
  public var didEndDecelerating: ((_ visibleDayRange: DayComponentsRange) -> Void)?

  /// Called when the user-driven scope gesture changes the scope.
  ///
  /// Use this to keep application state synchronized with the view.
  public var scopeChangeHandler: ((_ scope: CalendarViewScope) -> Void)?

  /// Called before a scope transition when the calendar's container should change height.
  public var preferredHeightChangeHandler: ((CalendarViewScopeHeightChange) -> Void)?

  /// Enables an upward gesture to collapse to a week and a downward gesture to expand to a month.
  public var isScopeGestureEnabled = true {
    didSet {
      scopePanGestureRecognizer.isEnabled = isScopeGestureEnabled
    }
  }

  /// Whether a day selection in month scope automatically collapses the calendar to week scope.
  public var collapsesToWeekOnDaySelection = false

  /// The pan gesture recognizer that controls month/week scope changes.
  public let scopePanGestureRecognizer = UIPanGestureRecognizer()

  /// The currently visible day range for the active scope.
  public var visibleDayRange: DayComponentsRange? {
    switch scope {
    case .month:
      monthCalendarView.visibleDayRange
    case .week:
      weekCalendarView.visibleDayRange
    }
  }

  /// The currently visible month range in month scope.
  public var visibleMonthRange: MonthComponentsRange? {
    monthCalendarView.visibleMonthRange
  }

  public override var layoutMargins: UIEdgeInsets {
    didSet {
      synchronizeLayoutMargins()
    }
  }

  public override var directionalLayoutMargins: NSDirectionalEdgeInsets {
    didSet {
      synchronizeLayoutMargins()
    }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    monthCalendarView.frame = bounds
    weekCalendarView.frame = bounds
  }

  /// Updates the content in both month and week scopes.
  public func setContent(_ content: CalendarViewContent, animated: Bool = false) {
    self.content = content
    monthCalendarView.setContent(content, animated: animated)
    weekCalendarView.setContent(content)
    scroll(toDayContaining: anchorDate, scrollPosition: .centered, animated: false)
    invalidateIntrinsicContentSize()
  }

  /// Changes the visible scope while keeping `date` as the transition anchor.
  public func setScope(
    _ scope: CalendarViewScope,
    anchoredAt date: Date,
    animated: Bool
  ) {
    anchorDate = clampedDate(date)
    guard scope != self.scope else {
      scroll(toDayContaining: anchorDate, scrollPosition: .centered, animated: animated)
      return
    }

    let oldScope = self.scope
    self.scope = scope
    prepareTargetScope(scope, anchorDate: anchorDate)

    let duration = animated ? Self.scopeAnimationDuration : 0
    preferredHeightChangeHandler?(
      CalendarViewScopeHeightChange(
        scope: scope,
        height: preferredHeight(forWidth: bounds.width, scope: scope),
        animationDuration: duration,
        animated: animated
      )
    )

    guard animated, window != nil else {
      configureVisibility(for: scope)
      scopeChangeHandler?(scope)
      invalidateIntrinsicContentSize()
      return
    }

    transition(from: oldScope, to: scope, anchorDate: anchorDate, duration: duration)
  }

  /// Returns the preferred height for the current scope and supplied width.
  public func preferredHeight(forWidth width: CGFloat) -> CGFloat {
    preferredHeight(forWidth: width, scope: scope)
  }

  /// Scrolls the active month and week renderers to the supplied day.
  public func scroll(
    toDayContaining date: Date,
    scrollPosition: CalendarViewScrollPosition,
    animated: Bool
  ) {
    anchorDate = clampedDate(date)
    monthCalendarView.scroll(
      toDayContaining: anchorDate,
      scrollPosition: scrollPosition,
      animated: animated && scope == .month
    )
    weekCalendarView.scroll(
      toDay: content.calendar.day(containing: anchorDate),
      animated: animated && scope == .week
    )
  }

  /// Scrolls month scope to the supplied month.
  public func scroll(
    toMonthContaining date: Date,
    scrollPosition: CalendarViewScrollPosition,
    animated: Bool
  ) {
    monthCalendarView.scroll(
      toMonthContaining: date,
      scrollPosition: scrollPosition,
      animated: animated
    )
  }

  // MARK: Private

  private static let scopeAnimationDuration: TimeInterval = 0.34
  private static let scopeGestureThreshold: CGFloat = 44

  private var content: CalendarViewContent
  private var anchorDate: Date
  private let monthCalendarView: CalendarView
  private let weekCalendarView: WeekCalendarView

  private func installScrollHandlers() {
    monthCalendarView.didScroll = { [weak self] range, isUserDragging in
      guard self?.scope == .month else { return }
      self?.didScroll?(range, isUserDragging)
    }
    monthCalendarView.didEndDragging = { [weak self] range, willDecelerate in
      guard self?.scope == .month else { return }
      self?.didEndDragging?(range, willDecelerate)
    }
    monthCalendarView.didEndDecelerating = { [weak self] range in
      guard self?.scope == .month else { return }
      self?.didEndDecelerating?(range)
    }

    weekCalendarView.didScroll = { [weak self] range, isUserDragging in
      guard self?.scope == .week else { return }
      self?.didScroll?(range, isUserDragging)
    }
    weekCalendarView.didEndDragging = { [weak self] range, willDecelerate in
      guard self?.scope == .week else { return }
      self?.didEndDragging?(range, willDecelerate)
    }
    weekCalendarView.didEndDecelerating = { [weak self] range in
      guard self?.scope == .week else { return }
      self?.didEndDecelerating?(range)
    }
  }

  private func synchronizeLayoutMargins() {
    monthCalendarView.layoutMargins = layoutMargins
    weekCalendarView.layoutMargins = layoutMargins
    setNeedsLayout()
    invalidateIntrinsicContentSize()
  }

  private func handleDaySelection(_ day: Day) {
    anchorDate = content.calendar.startDate(of: day)
    daySelectionHandler?(day)

    if scope == .month, collapsesToWeekOnDaySelection {
      setScope(.week, anchoredAt: anchorDate, animated: true)
    }
  }

  private func clampedDate(_ date: Date) -> Date {
    let day = content.calendar.day(containing: date)
    let clampedDay = min(max(day, content.dayRange.lowerBound), content.dayRange.upperBound)
    return content.calendar.startDate(of: clampedDay)
  }

  private func preferredHeight(forWidth width: CGFloat, scope: CalendarViewScope) -> CGFloat {
    guard width > 0 else { return UIView.noIntrinsicMetric }

    switch scope {
    case .month:
      let horizontallyInsetWidth = max(width - layoutMargins.left - layoutMargins.right, 0)
      return
        monthCalendarView
        .intrinsicContentSize(forHorizontallyInsetWidth: horizontallyInsetWidth)
        .height

    case .week:
      return weekCalendarView.preferredHeight(forWidth: width)
    }
  }

  private func prepareTargetScope(_ scope: CalendarViewScope, anchorDate: Date) {
    switch scope {
    case .month:
      monthCalendarView.scroll(
        toDayContaining: anchorDate,
        scrollPosition: .centered,
        animated: false
      )
      monthCalendarView.isHidden = false

    case .week:
      weekCalendarView.scroll(
        toDay: content.calendar.day(containing: anchorDate),
        animated: false
      )
      weekCalendarView.isHidden = false
    }

    layoutIfNeeded()
  }

  private func configureVisibility(for scope: CalendarViewScope) {
    monthCalendarView.alpha = scope == .month ? 1 : 0
    monthCalendarView.isHidden = scope != .month
    monthCalendarView.transform = .identity

    weekCalendarView.alpha = scope == .week ? 1 : 0
    weekCalendarView.isHidden = scope != .week
    weekCalendarView.transform = .identity
  }

  private func transition(
    from oldScope: CalendarViewScope,
    to newScope: CalendarViewScope,
    anchorDate: Date,
    duration: TimeInterval
  ) {
    let selectedDayFrame = monthCalendarView.frameOfVisibleDay(containing: anchorDate)
    let translation = max((selectedDayFrame?.minY ?? bounds.midY) - bounds.minY, 0)

    monthCalendarView.isHidden = false
    weekCalendarView.isHidden = false

    if newScope == .week {
      weekCalendarView.alpha = 0
      weekCalendarView.transform = CGAffineTransform(translationX: 0, y: translation)
      monthCalendarView.alpha = 1
      monthCalendarView.transform = .identity
    } else {
      monthCalendarView.alpha = 0
      monthCalendarView.transform = CGAffineTransform(translationX: 0, y: -translation * 0.35)
      weekCalendarView.alpha = 1
      weekCalendarView.transform = .identity
    }

    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
    ) {
      if newScope == .week {
        self.weekCalendarView.alpha = 1
        self.weekCalendarView.transform = .identity
        self.monthCalendarView.alpha = 0
        self.monthCalendarView.transform = CGAffineTransform(
          translationX: 0,
          y: -translation * 0.2
        )
      } else {
        self.monthCalendarView.alpha = 1
        self.monthCalendarView.transform = .identity
        self.weekCalendarView.alpha = 0
        self.weekCalendarView.transform = CGAffineTransform(translationX: 0, y: translation)
      }
    } completion: { _ in
      self.configureVisibility(for: newScope)
      self.scopeChangeHandler?(newScope)
      self.invalidateIntrinsicContentSize()
    }
  }

  @objc
  private func handleScopePan(_ gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.state == .ended else { return }

    let translation = gestureRecognizer.translation(in: self)
    let velocity = gestureRecognizer.velocity(in: self)
    let projectedTranslation = translation.y + (velocity.y * 0.08)

    switch scope {
    case .month where projectedTranslation < -Self.scopeGestureThreshold:
      setScope(.week, anchoredAt: anchorDate, animated: true)

    case .week where projectedTranslation > Self.scopeGestureThreshold:
      setScope(.month, anchoredAt: anchorDate, animated: true)

    default:
      break
    }
  }

  public override func gestureRecognizerShouldBegin(
    _ gestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    guard
      gestureRecognizer === scopePanGestureRecognizer,
      let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer
    else {
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    let velocity = panGestureRecognizer.velocity(in: self)
    guard abs(velocity.y) > abs(velocity.x) else { return false }

    switch scope {
    case .month:
      return velocity.y < 0
    case .week:
      return velocity.y > 0
    }
  }
}

// MARK: UIGestureRecognizerDelegate

extension CalendarScopeView {

  public func gestureRecognizer(
    _: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    true
  }
}
