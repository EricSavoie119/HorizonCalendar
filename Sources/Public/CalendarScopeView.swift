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
    monthCalendarView.setDayOfWeekItemsAlpha(0)

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
    scrollScopes(toAnchorDate: anchorDate, animated: false)
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

  /// Receives per-frame geometry while an animated scope transition runs.
  @_spi(Instrumentation)
  public var scopeTransitionDebugHandler:
    ((CalendarViewScopeTransitionDebugSnapshot) -> Void)?

  /// Enables an upward gesture to collapse to a week and a downward gesture to expand to a month.
  ///
  /// When enabled, vertical gestures that begin inside the calendar take precedence over an
  /// enclosing scroll view, preventing pull-to-refresh and vertical scrolling from stealing them.
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
    let intrinsicMonthHeight = monthLayoutHeight(forWidth: bounds.width)
    let monthHeight = transitionMonthHeight
      ?? (intrinsicMonthHeight > 0 ? intrinsicMonthHeight : bounds.height)
    monthCalendarView.frame = CGRect(
      x: bounds.minX,
      y: bounds.minY,
      width: bounds.width,
      height: monthHeight
    )
    weekCalendarView.frame = bounds

    if let transitionClipView {
      transitionClipView.frame = transitionClipFrame(
        top: transitionClipView.frame.minY
      )
    }
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    claimVerticalGesturesFromEnclosingScrollView()
  }

  /// Updates the content in both month and week scopes.
  public func setContent(_ content: CalendarViewContent, animated: Bool = false) {
    self.content = content
    cachedMonthLayoutHeight = nil
    monthCalendarView.setContent(content, animated: animated)
    weekCalendarView.setContent(content)
    scrollScopes(toAnchorDate: anchorDate, animated: false)
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
      scrollScopes(toAnchorDate: anchorDate, animated: animated)
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
  private weak var enclosingScrollView: UIScrollView?
  private var transitionMonthHeight: CGFloat?
  private var cachedMonthLayoutHeight: (width: CGFloat, height: CGFloat)?
  private var transitionDebugContext: TransitionDebugContext?
  private var transitionDebugDisplayLink: CADisplayLink?
  private weak var transitionClipView: UIView?
  private weak var transitionDebugBackdropView: UIView?
  private weak var transitionDebugMatchedRowView: UIView?

  private func claimVerticalGesturesFromEnclosingScrollView() {
    var ancestor = superview

    while let currentAncestor = ancestor {
      if let scrollView = currentAncestor as? UIScrollView {
        guard enclosingScrollView !== scrollView else { return }
        scrollView.panGestureRecognizer.require(toFail: scopePanGestureRecognizer)
        enclosingScrollView = scrollView
        return
      }

      ancestor = currentAncestor.superview
    }
  }

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
    cachedMonthLayoutHeight = nil
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
      return monthLayoutHeight(forWidth: width)

    case .week:
      return weekCalendarView.preferredHeight(forWidth: width)
    }
  }

  private func monthLayoutHeight(forWidth width: CGFloat) -> CGFloat {
    guard width > 0 else { return UIView.noIntrinsicMetric }
    if let cachedMonthLayoutHeight, cachedMonthLayoutHeight.width == width {
      return cachedMonthLayoutHeight.height
    }

    let horizontallyInsetWidth = max(width - layoutMargins.left - layoutMargins.right, 0)
    let height = monthCalendarView
      .intrinsicContentSize(forHorizontallyInsetWidth: horizontallyInsetWidth)
      .height
    cachedMonthLayoutHeight = (width, height)
    return height
  }

  private func prepareTargetScope(_ scope: CalendarViewScope, anchorDate: Date) {
    switch scope {
    case .month:
      monthCalendarView.scroll(
        toMonthContaining: anchorDate,
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

  private func scrollScopes(toAnchorDate anchorDate: Date, animated: Bool) {
    monthCalendarView.scroll(
      toMonthContaining: anchorDate,
      scrollPosition: .centered,
      animated: animated && scope == .month
    )
    weekCalendarView.scroll(
      toDay: content.calendar.day(containing: anchorDate),
      animated: animated && scope == .week
    )
  }

  private func configureVisibility(for scope: CalendarViewScope) {
    monthCalendarView.setDayOfWeekItemsAlpha(0)
    monthCalendarView.alpha = scope == .month ? 1 : 0
    monthCalendarView.isHidden = scope != .month
    monthCalendarView.transform = .identity

    // The week renderer owns the one shared weekday header in both scopes. In month scope, only its
    // date content is hidden and interaction passes through to the month renderer below it.
    weekCalendarView.alpha = 1
    weekCalendarView.isHidden = false
    weekCalendarView.isUserInteractionEnabled = scope == .week
    weekCalendarView.setDayContentAlpha(scope == .week ? 1 : 0)
    weekCalendarView.transform = .identity
  }

  private func transition(
    from oldScope: CalendarViewScope,
    to newScope: CalendarViewScope,
    anchorDate: Date,
    duration: TimeInterval
  ) {
    transitionMonthHeight = preferredHeight(forWidth: bounds.width, scope: .month)
    setNeedsLayout()
    layoutIfNeeded()
    prepareTargetScope(newScope, anchorDate: anchorDate)

    guard
      let monthDayFrame = monthCalendarView.frameOfVisibleDay(containing: anchorDate),
      let weekDayFrame = weekCalendarView.frameOfVisibleDay(
        content.calendar.day(containing: anchorDate)
      )
    else {
      transitionMonthHeight = nil
      configureVisibility(for: newScope)
      scopeChangeHandler?(newScope)
      invalidateIntrinsicContentSize()
      return
    }

    let monthRowFrame = CGRect(
      x: monthCalendarView.bounds.minX,
      y: monthDayFrame.minY,
      width: monthCalendarView.bounds.width,
      height: monthDayFrame.height
    )
    let weekRowFrame = CGRect(
      x: weekCalendarView.bounds.minX,
      y: weekDayFrame.minY,
      width: weekCalendarView.bounds.width,
      height: weekDayFrame.height
    )
    monthCalendarView.isHidden = false
    weekCalendarView.isHidden = false
    monthCalendarView.alpha = 1
    weekCalendarView.alpha = 1
    monthCalendarView.transform = .identity
    weekCalendarView.transform = .identity

    // Keep the permanent weekday labels stationary in the live week renderer. The month backdrop
    // is captured without its duplicate labels.
    monthCalendarView.setDayOfWeekItemsAlpha(0)
    weekCalendarView.setDayContentAlpha(1)

    guard
      let backdropImage = monthCalendarView.snapshotImage(excluding: monthRowFrame),
      let matchedRowImage = (oldScope == .month
        ? monthCalendarView.snapshotImage(in: monthRowFrame)
        : weekCalendarView.snapshotImage(in: weekRowFrame))
    else {
      transitionMonthHeight = nil
      configureVisibility(for: newScope)
      scopeChangeHandler?(newScope)
      invalidateIntrinsicContentSize()
      return
    }

    let clipFrame = transitionClipFrame(top: weekRowFrame.minY)
    let clipView = UIView(frame: clipFrame)
    clipView.clipsToBounds = true
    clipView.isUserInteractionEnabled = false
    clipView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    let monthBackdropFrame = monthCalendarView.frame.offsetBy(
      dx: -clipFrame.minX,
      dy: -clipFrame.minY
    )
    let rowScaleX = weekRowFrame.width / monthRowFrame.width
    let rowScaleY = weekRowFrame.height / monthRowFrame.height
    let collapsedBackdropFrameInCalendar = CGRect(
      x: weekRowFrame.minX - ((monthRowFrame.minX - monthCalendarView.bounds.minX) * rowScaleX),
      y: weekRowFrame.minY - ((monthRowFrame.minY - monthCalendarView.bounds.minY) * rowScaleY),
      width: monthCalendarView.bounds.width * rowScaleX,
      height: monthCalendarView.bounds.height * rowScaleY
    )
    let weekBackdropFrame = collapsedBackdropFrameInCalendar.offsetBy(
      dx: -clipFrame.minX,
      dy: -clipFrame.minY
    )

    let backdropView = UIImageView(image: backdropImage)
    backdropView.frame = oldScope == .month ? monthBackdropFrame : weekBackdropFrame
    backdropView.contentMode = .scaleToFill
    backdropView.isUserInteractionEnabled = false

    let matchedRowView = UIImageView(image: matchedRowImage)
    let monthMatchedRowFrame = monthRowFrame.offsetBy(
      dx: -clipFrame.minX,
      dy: -clipFrame.minY
    )
    let weekMatchedRowFrame = weekRowFrame.offsetBy(
      dx: -clipFrame.minX,
      dy: -clipFrame.minY
    )
    matchedRowView.frame = oldScope == .month ? monthMatchedRowFrame : weekMatchedRowFrame
    matchedRowView.contentMode = .scaleToFill
    matchedRowView.isUserInteractionEnabled = false

    monthCalendarView.isHidden = true
    weekCalendarView.setDayContentAlpha(0)
    clipView.addSubview(backdropView)
    clipView.addSubview(matchedRowView)
    addSubview(clipView)
    transitionClipView = clipView
    transitionDebugBackdropView = backdropView
    transitionDebugMatchedRowView = matchedRowView
    beginTransitionDebugging(
      from: oldScope,
      to: newScope,
      duration: duration,
      monthAnchorFrame: monthDayFrame,
      weekAnchorFrame: weekDayFrame
    )

    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
    ) {
      backdropView.frame = newScope == .month ? monthBackdropFrame : weekBackdropFrame
      matchedRowView.frame = newScope == .month ? monthMatchedRowFrame : weekMatchedRowFrame
    } completion: { _ in
      self.finishTransitionDebugging()
      clipView.removeFromSuperview()
      self.transitionClipView = nil
      self.transitionDebugBackdropView = nil
      self.transitionDebugMatchedRowView = nil
      self.transitionMonthHeight = nil
      self.configureVisibility(for: newScope)
      self.setNeedsLayout()
      self.scopeChangeHandler?(newScope)
      self.invalidateIntrinsicContentSize()
    }
    startTransitionDebugDisplayLink()
  }

  private func transitionClipFrame(top: CGFloat) -> CGRect {
    CGRect(
      x: bounds.minX,
      y: top,
      width: bounds.width,
      height: max(bounds.maxY - top, 0)
    )
  }

  private func beginTransitionDebugging(
    from oldScope: CalendarViewScope,
    to newScope: CalendarViewScope,
    duration: TimeInterval,
    monthAnchorFrame: CGRect,
    weekAnchorFrame: CGRect
  ) {
    guard scopeTransitionDebugHandler != nil else { return }

    transitionDebugDisplayLink?.invalidate()
    transitionDebugContext = TransitionDebugContext(
      fromScope: oldScope,
      toScope: newScope,
      startTime: CACurrentMediaTime(),
      duration: duration,
      monthAnchorFrame: monthAnchorFrame,
      weekAnchorFrame: weekAnchorFrame
    )
    emitTransitionDebugSnapshot(phase: .started)
  }

  private func startTransitionDebugDisplayLink() {
    guard transitionDebugContext != nil, scopeTransitionDebugHandler != nil else { return }

    let displayLink = CADisplayLink(target: self, selector: #selector(debugDisplayLinkFired))
    displayLink.add(to: .main, forMode: .common)
    transitionDebugDisplayLink = displayLink
  }

  private func finishTransitionDebugging() {
    guard transitionDebugContext != nil else { return }
    emitTransitionDebugSnapshot(phase: .completed)
    transitionDebugDisplayLink?.invalidate()
    transitionDebugDisplayLink = nil
    transitionDebugContext = nil
  }

  @objc
  private func debugDisplayLinkFired() {
    emitTransitionDebugSnapshot(phase: .running)
  }

  private func emitTransitionDebugSnapshot(
    phase: CalendarViewScopeTransitionDebugSnapshot.Phase
  ) {
    guard
      let transitionDebugContext,
      let scopeTransitionDebugHandler
    else {
      return
    }

    let containerPresentationLayer = layer.presentation() ?? layer
    let monthPresentationLayer = monthCalendarView.layer.presentation() ?? monthCalendarView.layer
    let weekPresentationLayer = weekCalendarView.layer.presentation() ?? weekCalendarView.layer
    let maskLayer = transitionClipView?.layer
    let maskPresentationLayer = maskLayer?.presentation() ?? maskLayer
    let backdropLayer = transitionDebugBackdropView?.layer
    let backdropPresentationLayer = backdropLayer?.presentation() ?? backdropLayer
    let matchedRowLayer = transitionDebugMatchedRowView?.layer
    let matchedRowPresentationLayer = matchedRowLayer?.presentation() ?? matchedRowLayer
    let clipModelOrigin = transitionClipView?.frame.origin ?? .zero
    let clipPresentationOrigin = maskPresentationLayer?.frame.origin ?? clipModelOrigin
    let backdropFrame = transitionDebugBackdropView?.frame.offsetBy(
      dx: clipModelOrigin.x,
      dy: clipModelOrigin.y
    )
    let backdropPresentationFrame = backdropPresentationLayer?.frame.offsetBy(
      dx: clipPresentationOrigin.x,
      dy: clipPresentationOrigin.y
    )
    let matchedRowFrame = transitionDebugMatchedRowView?.frame.offsetBy(
      dx: clipModelOrigin.x,
      dy: clipModelOrigin.y
    )
    let matchedRowPresentationFrame = matchedRowPresentationLayer?.frame.offsetBy(
      dx: clipPresentationOrigin.x,
      dy: clipPresentationOrigin.y
    )

    let monthAnchorCenter = CGPoint(
      x: transitionDebugContext.monthAnchorFrame.midX,
      y: transitionDebugContext.monthAnchorFrame.midY
    )
    let weekAnchorCenter = CGPoint(
      x: transitionDebugContext.weekAnchorFrame.midX,
      y: transitionDebugContext.weekAnchorFrame.midY
    )
    let monthPresentationFrame = monthPresentationLayer.frame
    let weekPresentationFrame = weekPresentationLayer.frame

    scopeTransitionDebugHandler(
      CalendarViewScopeTransitionDebugSnapshot(
        phase: phase,
        fromScope: transitionDebugContext.fromScope,
        toScope: transitionDebugContext.toScope,
        elapsedTime: CACurrentMediaTime() - transitionDebugContext.startTime,
        duration: transitionDebugContext.duration,
        containerBounds: bounds,
        containerPresentationFrame: containerPresentationLayer.frame,
        monthFrame: monthCalendarView.frame,
        monthPresentationFrame: monthPresentationFrame,
        monthTransform: monthCalendarView.transform,
        monthPresentationTransform: monthPresentationLayer.affineTransform(),
        weekFrame: weekCalendarView.frame,
        weekPresentationFrame: weekPresentationFrame,
        monthMaskFrame: maskLayer?.frame,
        monthMaskPresentationFrame: maskPresentationLayer?.frame,
        transitionBackdropFrame: backdropFrame,
        transitionBackdropPresentationFrame: backdropPresentationFrame,
        matchedRowFrame: matchedRowFrame,
        matchedRowPresentationFrame: matchedRowPresentationFrame,
        monthAnchorFrame: transitionDebugContext.monthAnchorFrame,
        weekAnchorFrame: transitionDebugContext.weekAnchorFrame,
        monthAnchorPresentationCenter: monthAnchorCenter.applying(
          monthPresentationLayer.affineTransform()
        ),
        weekAnchorPresentationCenter: weekAnchorCenter.applying(
          weekPresentationLayer.affineTransform()
        )
      )
    )
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
    return abs(velocity.y) > abs(velocity.x)
  }
}

private struct TransitionDebugContext {
  let fromScope: CalendarViewScope
  let toScope: CalendarViewScope
  let startTime: CFTimeInterval
  let duration: TimeInterval
  let monthAnchorFrame: CGRect
  let weekAnchorFrame: CGRect
}

private extension UIView {

  func snapshotImage(in rect: CGRect) -> UIImage? {
    guard rect.width > 0, rect.height > 0 else { return nil }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = window?.screen.scale ?? traitCollection.displayScale
    format.opaque = false
    return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
      context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
      layer.render(in: context.cgContext)
    }
  }

  func snapshotImage(excluding rect: CGRect) -> UIImage? {
    guard bounds.width > 0, bounds.height > 0 else { return nil }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = window?.screen.scale ?? traitCollection.displayScale
    format.opaque = false
    return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
      layer.render(in: context.cgContext)
      context.cgContext.clear(rect)
    }
  }
}
