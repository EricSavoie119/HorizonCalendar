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

// MARK: - WeekCalendarView

final class WeekCalendarView: UIView {

  // MARK: Lifecycle

  init(initialContent: CalendarViewContent) {
    content = initialContent
    weekData = WeekData(content: initialContent)

    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumLineSpacing = 0
    layout.minimumInteritemSpacing = 0
    collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

    super.init(frame: .zero)

    collectionView.backgroundColor = .clear
    collectionView.alwaysBounceHorizontal = true
    collectionView.alwaysBounceVertical = false
    collectionView.decelerationRate = .fast
    collectionView.isPagingEnabled = true
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.register(
      WeekPageCollectionViewCell.self,
      forCellWithReuseIdentifier: WeekPageCollectionViewCell.reuseIdentifier
    )

    addSubview(collectionView)
    rebuildDayOfWeekViews()
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Internal

  var daySelectionHandler: ((DayComponents) -> Void)?
  var didScroll: ((_ visibleDayRange: DayComponentsRange, _ isUserDragging: Bool) -> Void)?
  var didEndDragging: ((_ visibleDayRange: DayComponentsRange, _ willDecelerate: Bool) -> Void)?
  var didEndDecelerating: ((_ visibleDayRange: DayComponentsRange) -> Void)?

  private(set) var anchorDay: Day?

  override func layoutMarginsDidChange() {
    super.layoutMarginsDidChange()
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let metrics = WeekLayoutMetrics(
      content: content,
      width: bounds.width,
      layoutMargins: directionalLayoutMargins
    )

    for (index, view) in dayOfWeekViews.enumerated() {
      view.frame = metrics.frameForDay(at: index, rowOriginY: metrics.dayOfWeekOriginY)
    }

    separatorView.frame = metrics.separatorFrame
    collectionView.frame = metrics.collectionViewFrame

    if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
      let itemSize = collectionView.bounds.size
      if layout.itemSize != itemSize {
        layout.itemSize = itemSize
        layout.invalidateLayout()
      }
    }

    applyPendingScrollIfNeeded()
  }

  func setContent(_ content: CalendarViewContent) {
    let previousAnchorDay = visibleDayRange?.lowerBound ?? anchorDay
    self.content = content
    weekData = WeekData(content: content)
    rebuildDayOfWeekViews()
    collectionView.reloadData()

    if let previousAnchorDay {
      scroll(toDay: previousAnchorDay, animated: false)
    }

    setNeedsLayout()
  }

  func preferredHeight(forWidth width: CGFloat) -> CGFloat {
    WeekLayoutMetrics(
      content: content,
      width: width,
      layoutMargins: directionalLayoutMargins
    ).preferredHeight
  }

  func scroll(toDay day: Day, animated: Bool) {
    let targetDay = min(max(day, content.dayRange.lowerBound), content.dayRange.upperBound)
    anchorDay = targetDay
    pendingScroll = (weekData.weekIndex(containing: targetDay), animated)
    applyPendingScrollIfNeeded()
  }

  var visibleDayRange: DayRange? {
    guard weekData.weekCount > 0 else { return nil }

    let pageWidth = collectionView.bounds.width
    let rawIndex = pageWidth > 0 ? collectionView.contentOffset.x / pageWidth : 0
    let pageIndex = min(max(Int(rawIndex.rounded()), 0), weekData.weekCount - 1)
    return weekData.visibleDayRange(forWeekAt: pageIndex)
  }

  // MARK: Private

  private var content: CalendarViewContent
  private var weekData: WeekData
  private let collectionView: UICollectionView
  private var dayOfWeekViews = [ItemView]()
  private let separatorView = UIView()
  private var pendingScroll: (index: Int, animated: Bool)?

  private func rebuildDayOfWeekViews() {
    for view in dayOfWeekViews {
      view.removeFromSuperview()
    }
    dayOfWeekViews.removeAll(keepingCapacity: true)

    for positionRawValue in 1...DayOfWeekPosition.numberOfPositions {
      guard let position = DayOfWeekPosition(rawValue: positionRawValue) else {
        preconditionFailure("Could not create day-of-week position \(positionRawValue).")
      }
      let weekdayIndex = content.calendar.weekdayIndex(for: position)
      let model = content.dayOfWeekItemProvider(nil, weekdayIndex)
      let itemView = ItemView(initialCalendarItemModel: model)
      itemView.isUserInteractionEnabled = false
      addSubview(itemView)
      dayOfWeekViews.append(itemView)
    }

    if let separatorOptions = content.daysOfTheWeekRowSeparatorOptions {
      separatorView.backgroundColor = separatorOptions.color
      separatorView.isHidden = false
    } else {
      separatorView.isHidden = true
    }
    addSubview(separatorView)
  }

  private func applyPendingScrollIfNeeded() {
    guard
      let pendingScroll,
      collectionView.bounds.width > 0,
      pendingScroll.index >= 0,
      pendingScroll.index < weekData.weekCount
    else {
      return
    }

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
      at: IndexPath(item: pendingScroll.index, section: 0),
      at: .centeredHorizontally,
      animated: pendingScroll.animated
    )
    self.pendingScroll = nil
  }

  private func notifyDidScroll(isUserDragging: Bool) {
    guard let visibleDayRange else { return }
    anchorDay = visibleDayRange.lowerBound
    didScroll?(visibleDayRange, isUserDragging)
  }
}

// MARK: UICollectionViewDataSource

extension WeekCalendarView: UICollectionViewDataSource {

  func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
    weekData.weekCount
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    guard
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: WeekPageCollectionViewCell.reuseIdentifier,
        for: indexPath
      ) as? WeekPageCollectionViewCell
    else {
      preconditionFailure("Could not dequeue a WeekPageCollectionViewCell.")
    }

    cell.configure(
      days: weekData.days(inWeekAt: indexPath.item),
      content: content,
      selectionHandler: { [weak self] day in
        self?.anchorDay = day
        self?.daySelectionHandler?(day)
      }
    )
    return cell
  }
}

// MARK: UICollectionViewDelegate

extension WeekCalendarView: UICollectionViewDelegate {

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    notifyDidScroll(isUserDragging: scrollView.isDragging && scrollView.isTracking)
  }

  func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
    guard let visibleDayRange else { return }
    didEndDragging?(visibleDayRange, decelerate)
  }

  func scrollViewDidEndDecelerating(_: UIScrollView) {
    guard let visibleDayRange else { return }
    didEndDecelerating?(visibleDayRange)
  }
}

// MARK: - WeekPageCollectionViewCell

private final class WeekPageCollectionViewCell: UICollectionViewCell {

  static let reuseIdentifier = "WeekPageCollectionViewCell"

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(pageView)
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    pageView.frame = contentView.bounds
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    pageView.reset()
  }

  func configure(
    days: [Day?],
    content: CalendarViewContent,
    selectionHandler: @escaping (Day) -> Void
  ) {
    pageView.configure(days: days, content: content, selectionHandler: selectionHandler)
  }

  private let pageView = WeekPageView()
}

// MARK: - WeekPageView

private final class WeekPageView: UIView {

  func configure(
    days: [Day?],
    content: CalendarViewContent,
    selectionHandler: @escaping (Day) -> Void
  ) {
    reset()
    self.days = days
    self.content = content

    for day in days {
      guard let day else {
        dayBackgroundViews.append(nil)
        dayViews.append(nil)
        continue
      }

      let backgroundView = content.dayBackgroundItemProvider?(day).map {
        ItemView(initialCalendarItemModel: $0)
      }
      if let backgroundView {
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
      }
      dayBackgroundViews.append(backgroundView)

      let dayView = ItemView(initialCalendarItemModel: content.dayItemProvider(day))
      dayView.selectionHandler = { selectionHandler(day) }
      addSubview(dayView)
      dayViews.append(dayView)
    }

    setNeedsLayout()
  }

  func reset() {
    days = []
    content = nil

    for view in dayBackgroundViews.compactMap({ $0 }) {
      view.removeFromSuperview()
    }
    for view in dayRangeViews {
      view.removeFromSuperview()
    }
    for view in dayViews.compactMap({ $0 }) {
      view.removeFromSuperview()
    }

    dayBackgroundViews.removeAll(keepingCapacity: true)
    dayRangeViews.removeAll(keepingCapacity: true)
    dayViews.removeAll(keepingCapacity: true)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let content else { return }

    let metrics = WeekPageLayoutMetrics(content: content, bounds: bounds)
    var daysAndFrames = [(day: Day, frame: CGRect)]()

    for index in days.indices {
      let frame = metrics.frameForDay(at: index)
      dayBackgroundViews[index]?.frame = frame
      dayViews[index]?.frame = frame
      if let day = days[index] {
        daysAndFrames.append((day, frame))
      }
    }

    rebuildDayRangeViews(daysAndFrames: daysAndFrames, content: content)
  }

  private var days = [Day?]()
  private var content: CalendarViewContent?
  private var dayBackgroundViews = [ItemView?]()
  private var dayRangeViews = [ItemView]()
  private var dayViews = [ItemView?]()

  private func rebuildDayRangeViews(
    daysAndFrames: [(day: Day, frame: CGRect)],
    content: CalendarViewContent
  ) {
    for view in dayRangeViews {
      view.removeFromSuperview()
    }
    dayRangeViews.removeAll(keepingCapacity: true)

    guard
      let dayRangesAndItemProvider = content.dayRangesAndItemProvider,
      let firstDay = daysAndFrames.first?.day,
      let lastDay = daysAndFrames.last?.day
    else {
      return
    }

    let visibleRange = firstDay...lastDay
    for dayRange in dayRangesAndItemProvider.dayRanges where dayRange.overlaps(visibleRange) {
      let visibleDaysAndFrames = daysAndFrames.filter { dayRange.contains($0.day) }
      guard let firstFrame = visibleDaysAndFrames.first?.frame else { continue }

      let unionFrame = visibleDaysAndFrames.dropFirst().reduce(firstFrame) {
        $0.union($1.frame)
      }
      let transform = CGAffineTransform(
        translationX: -unionFrame.minX,
        y: -unionFrame.minY
      )
      let context = DayRangeLayoutContext(
        dayRange: dayRange,
        daysAndFrames: visibleDaysAndFrames.map {
          ($0.day, $0.frame.applying(transform))
        },
        boundingUnionRectOfDayFrames: unionFrame.applying(transform)
      )
      let rangeView = ItemView(
        initialCalendarItemModel: dayRangesAndItemProvider.dayRangeItemProvider(context)
      )
      rangeView.frame = unionFrame
      rangeView.isUserInteractionEnabled = false
      insertSubview(rangeView, belowSubview: dayViews.compactMap({ $0 }).first ?? self)
      dayRangeViews.append(rangeView)
    }
  }
}

// MARK: - WeekData

struct WeekData {

  init(content: CalendarViewContent) {
    calendar = content.calendar
    dayRange = content.dayRange
    firstWeekStart = calendar.startOfWeek(containing: dayRange.lowerBound)
    let lastWeekStart = calendar.startOfWeek(containing: dayRange.upperBound)
    weekCount = calendar.numberOfWeeks(from: firstWeekStart, through: lastWeekStart)
  }

  let calendar: Calendar
  let dayRange: DayRange
  let firstWeekStart: Day
  let weekCount: Int

  func weekIndex(containing day: Day) -> Int {
    let weekStart = calendar.startOfWeek(containing: day)
    return min(
      max(calendar.numberOfWeeks(from: firstWeekStart, through: weekStart) - 1, 0),
      max(weekCount - 1, 0)
    )
  }

  func days(inWeekAt index: Int) -> [Day?] {
    let weekStart = calendar.day(byAddingDays: index * 7, to: firstWeekStart)
    return (0..<DayOfWeekPosition.numberOfPositions).map { dayOffset in
      let day = calendar.day(byAddingDays: dayOffset, to: weekStart)
      return dayRange.contains(day) ? day : nil
    }
  }

  func visibleDayRange(forWeekAt index: Int) -> DayRange? {
    let days = days(inWeekAt: index).compactMap { $0 }
    guard let firstDay = days.first, let lastDay = days.last else { return nil }
    return firstDay...lastDay
  }
}

// MARK: - Layout metrics

private struct WeekLayoutMetrics {

  init(
    content: CalendarViewContent,
    width: CGFloat,
    layoutMargins: NSDirectionalEdgeInsets
  ) {
    self.content = content
    self.width = width
    self.layoutMargins = layoutMargins

    let availableWidth =
      width - layoutMargins.leading - layoutMargins.trailing - content.monthDayInsets.leading
      - content.monthDayInsets.trailing - (content.horizontalDayMargin * 6)
    dayWidth = max(availableWidth / 7, 0)
  }

  let content: CalendarViewContent
  let width: CGFloat
  let layoutMargins: NSDirectionalEdgeInsets
  let dayWidth: CGFloat

  var dayOfWeekHeight: CGFloat {
    dayWidth * content.dayOfWeekAspectRatio
  }

  var dayHeight: CGFloat {
    dayWidth * content.dayAspectRatio
  }

  var dayOfWeekOriginY: CGFloat {
    layoutMargins.top + content.monthDayInsets.top
  }

  var collectionViewFrame: CGRect {
    CGRect(
      x: layoutMargins.leading + content.monthDayInsets.leading,
      y: dayOfWeekOriginY + dayOfWeekHeight + content.verticalDayMargin,
      width: max(
        width - layoutMargins.leading - layoutMargins.trailing - content.monthDayInsets.leading
          - content.monthDayInsets.trailing,
        0
      ),
      height: dayHeight
    )
  }

  var separatorFrame: CGRect {
    guard let options = content.daysOfTheWeekRowSeparatorOptions else { return .zero }
    return CGRect(
      x: collectionViewFrame.minX,
      y: dayOfWeekOriginY + dayOfWeekHeight - options.height,
      width: collectionViewFrame.width,
      height: options.height
    )
  }

  var preferredHeight: CGFloat {
    collectionViewFrame.maxY + content.monthDayInsets.bottom + layoutMargins.bottom
  }

  func frameForDay(at index: Int, rowOriginY: CGFloat) -> CGRect {
    CGRect(
      x: layoutMargins.leading + content.monthDayInsets.leading
        + (CGFloat(index) * (dayWidth + content.horizontalDayMargin)),
      y: rowOriginY,
      width: dayWidth,
      height: dayOfWeekHeight
    )
  }
}

private struct WeekPageLayoutMetrics {

  init(content: CalendarViewContent, bounds: CGRect) {
    self.content = content
    self.bounds = bounds
    dayWidth = max((bounds.width - (content.horizontalDayMargin * 6)) / 7, 0)
  }

  let content: CalendarViewContent
  let bounds: CGRect
  let dayWidth: CGFloat

  func frameForDay(at index: Int) -> CGRect {
    CGRect(
      x: CGFloat(index) * (dayWidth + content.horizontalDayMargin),
      y: 0,
      width: dayWidth,
      height: bounds.height
    )
  }
}
