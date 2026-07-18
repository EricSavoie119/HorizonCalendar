// Created by Bryan Keller on 5/31/20.
// Copyright © 2020 Airbnb Inc. All rights reserved.

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

@_spi(Instrumentation) import HorizonCalendar
import SwiftUI
import UIKit

// MARK: - AppDelegate

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?

  func application(
    _: UIApplication,
    didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    if ProcessInfo.processInfo.arguments.contains("--scope-transition-lab") {
      window?.rootViewController = UIHostingController(rootView: ScopeTransitionSwiftUILab())
    } else if ProcessInfo.processInfo.arguments.contains("--scope-transition-uikit-lab") {
      window?.rootViewController = ScopeTransitionLabViewController()
    } else {
      let demoPickerViewController = DemoPickerViewController()
      let navigationController = UINavigationController(rootViewController: demoPickerViewController)
      window?.rootViewController = navigationController
    }
    window?.makeKeyAndVisible()
    return true
  }

}

// MARK: - ScopeTransitionSwiftUILab

private struct ScopeTransitionSwiftUILab: View {

  @State private var scope = CalendarViewScope.month
  @State private var showsDetails = false

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        Text("Persistent content above calendar")
          .frame(maxWidth: .infinity, minHeight: 58)
          .foregroundStyle(.white)
          .background(.indigo, in: RoundedRectangle(cornerRadius: 16))

        ScopeTransitionSwiftUIRepresentable(
          scope: scope,
          setScope: { requestedScope in
            guard requestedScope != scope else { return }
            if requestedScope == .month {
              showsDetails = false
            }
            withAnimation(.easeInOut(duration: 0.34)) {
              scope = requestedScope
            }
          },
          transitionCompleted: { completedScope in
            guard completedScope == .week else { return }
            withAnimation(.easeOut(duration: 0.16)) {
              showsDetails = true
            }
          }
        )
        .frame(height: scope == .month ? 390 : 113.714)
        .animation(.easeInOut(duration: 0.34), value: scope)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))

        if scope == .week {
          Text("Selected-day details\nInserted only in week scope")
            .frame(maxWidth: .infinity, minHeight: 92)
            .foregroundStyle(.white)
            .background(.blue, in: RoundedRectangle(cornerRadius: 16))
            .opacity(showsDetails ? 1 : 0)
            .transition(.identity)
        }

        Text("Persistent content below calendar\nThis must be pushed by expansion.")
          .frame(maxWidth: .infinity, minHeight: 92)
          .foregroundStyle(.white)
          .background(.orange, in: RoundedRectangle(cornerRadius: 16))

        ScopeTransitionMarker()
          .frame(height: 1)

        Text("Automated SwiftUI host: month → week → month")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      .padding(16)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .task {
      print("SCOPE_SWIFTUI ready")
      try? await Task.sleep(for: .seconds(3))
      for cycle in 1...3 {
        print("SCOPE_SWIFTUI action cycle=\(cycle) direction=month_to_week")
        showsDetails = false
        withAnimation(.easeInOut(duration: 0.34)) {
          scope = .week
        }
        try? await Task.sleep(for: .seconds(1.2))
        print("SCOPE_SWIFTUI action cycle=\(cycle) direction=week_to_month")
        showsDetails = false
        withAnimation(.easeInOut(duration: 0.34)) {
          scope = .month
        }
        try? await Task.sleep(for: .seconds(1.2))
      }
      print("SCOPE_SWIFTUI complete cycles=3")
    }
  }
}

private struct ScopeTransitionSwiftUIRepresentable: UIViewRepresentable {

  let scope: CalendarViewScope
  let setScope: (CalendarViewScope) -> Void
  let transitionCompleted: (CalendarViewScope) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> CalendarScopeView {
    let calendarView = CalendarScopeView(
      initialContent: Self.content,
      initialScope: scope,
      initialDate: Self.anchorDate
    )
    calendarView.directionalLayoutMargins = .zero
    installHandlers(on: calendarView)
    context.coordinator.scope = scope
    return calendarView
  }

  func updateUIView(_ calendarView: CalendarScopeView, context: Context) {
    installHandlers(on: calendarView)
    guard context.coordinator.scope != scope else { return }
    context.coordinator.scope = scope
    calendarView.setScope(scope, anchoredAt: Self.anchorDate, animated: true)
  }

  private func installHandlers(on calendarView: CalendarScopeView) {
    calendarView.preferredHeightChangeHandler = { change in
      print(
        "SCOPE_SWIFTUI_HEIGHT scope=\(change.scope) target=\(Self.format(change.height)) duration=\(Self.format(change.animationDuration))"
      )
      setScope(change.scope)
    }
    calendarView.scopeChangeHandler = { completedScope in
      setScope(completedScope)
      transitionCompleted(completedScope)
    }
    guard !ProcessInfo.processInfo.arguments.contains("--scope-transition-no-debug") else {
      calendarView.scopeTransitionDebugHandler = nil
      return
    }
    calendarView.scopeTransitionDebugHandler = { snapshot in
      let marker = ScopeTransitionLabTelemetry.shared.marker
      let markerY = marker.flatMap { marker in
        marker.window?.convert(marker.bounds, from: marker).minY
      }
      print(
        "SCOPE_SWIFTUI_TRACE direction=\(snapshot.fromScope)_to_\(snapshot.toScope) phase=\(snapshot.phase.rawValue) elapsed=\(Self.format(snapshot.elapsedTime)) duration=\(Self.format(snapshot.duration)) containerModelH=\(Self.format(snapshot.containerBounds.height)) containerPresentationH=\(Self.format(snapshot.containerPresentationFrame.height)) matchedRowY=\(Self.format(snapshot.matchedRowPresentationFrame?.minY)) matchedRowH=\(Self.format(snapshot.matchedRowPresentationFrame?.height)) monthDayX=\(Self.format(snapshot.monthAnchorFrame.minX)) monthDayW=\(Self.format(snapshot.monthAnchorFrame.width)) monthRowY=\(Self.format(snapshot.monthAnchorFrame.minY)) monthRowH=\(Self.format(snapshot.monthAnchorFrame.height)) weekDayX=\(Self.format(snapshot.weekAnchorFrame.minX)) weekDayW=\(Self.format(snapshot.weekAnchorFrame.width)) weekRowY=\(Self.format(snapshot.weekAnchorFrame.minY)) weekRowH=\(Self.format(snapshot.weekAnchorFrame.height)) clipY=\(Self.format(snapshot.monthMaskPresentationFrame?.minY)) clipH=\(Self.format(snapshot.monthMaskPresentationFrame?.height)) backdropY=\(Self.format(snapshot.transitionBackdropPresentationFrame?.minY)) backdropH=\(Self.format(snapshot.transitionBackdropPresentationFrame?.height)) belowGlobalY=\(Self.format(markerY))"
      )
    }
  }

  final class Coordinator {
    var scope = CalendarViewScope.month
  }

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }()

  private static let anchorDate = calendar.date(
    from: DateComponents(year: 2026, month: 7, day: 18)
  )!

  private static let content: CalendarViewContent = {
    let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    let endDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
    return CalendarViewContent(
      calendar: calendar,
      visibleDateRange: startDate...endDate,
      monthsLayout: .horizontal(
        options: HorizontalMonthsLayoutOptions(
          maximumFullyVisibleMonths: 1,
          scrollingBehavior: .paginatedScrolling(.init(
            restingPosition: .atLeadingEdgeOfEachMonth,
            restingAffinity: .atPositionsClosestToTargetOffset
          ))
        )
      )
    )
    .interMonthSpacing(18)
    .verticalDayMargin(4)
    .horizontalDayMargin(4)
    .monthHeaderItemProvider { _ in
      Color.clear.frame(height: 0).calendarItemModel
    }
    .dayItemProvider { day in
      var properties = DayView.InvariantViewProperties.baseInteractive
      let date = calendar.date(from: day.components)!
      if calendar.isDate(date, inSameDayAs: anchorDate) {
        properties.backgroundShapeDrawingConfig.fillColor = .systemBlue
      } else if day.day.isMultiple(of: 3) {
        properties.backgroundShapeDrawingConfig.fillColor = .systemGreen.withAlphaComponent(0.22)
      }
      return DayView.calendarItemModel(
        invariantViewProperties: properties,
        content: .init(
          dayText: "\(day.day)",
          accessibilityLabel: nil,
          accessibilityHint: nil
        )
      )
    }
  }()

  private static func format(_ value: CGFloat?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.3f", value)
  }

  private static func format(_ value: TimeInterval) -> String {
    String(format: "%.4f", value)
  }
}

private final class ScopeTransitionLabTelemetry {
  static let shared = ScopeTransitionLabTelemetry()
  weak var marker: UIView?
}

private struct ScopeTransitionMarker: UIViewRepresentable {
  func makeUIView(context _: Context) -> UIView {
    let view = UIView()
    ScopeTransitionLabTelemetry.shared.marker = view
    return view
  }

  func updateUIView(_ uiView: UIView, context _: Context) {
    ScopeTransitionLabTelemetry.shared.marker = uiView
  }
}

// MARK: - ScopeTransitionLabViewController

private final class ScopeTransitionLabViewController: UIViewController {

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }()

  private lazy var anchorDate = calendar.date(
    from: DateComponents(year: 2026, month: 7, day: 18)
  )!

  private lazy var calendarView = CalendarScopeView(
    initialContent: makeContent(),
    initialScope: .month,
    initialDate: anchorDate
  )

  private let titleLabel = ScopeTransitionLabViewController.makeLabel(
    text: "Persistent content above calendar",
    color: .systemIndigo
  )
  private let detailsLabel = ScopeTransitionLabViewController.makeLabel(
    text: "Persistent content below calendar\nThis must be pushed by expansion.",
    color: .systemOrange
  )
  private let statusLabel = UILabel()
  private var calendarHeightConstraint: NSLayoutConstraint!
  private var hasStarted = false
  private var cycle = 0

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemGroupedBackground
    statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 0
    statusLabel.text = "Preparing deterministic scope transition lab…"

    calendarView.backgroundColor = .secondarySystemGroupedBackground
    calendarView.layer.cornerRadius = 18
    calendarView.directionalLayoutMargins = .zero
    calendarView.preferredHeightChangeHandler = { [weak self] change in
      guard let self else { return }
      calendarHeightConstraint.constant = change.height
      traceHeightRequest(change)

      guard change.animated else {
        view.layoutIfNeeded()
        return
      }

      UIView.animate(
        withDuration: change.animationDuration,
        delay: 0,
        options: [.beginFromCurrentState, .curveEaseInOut]
      ) {
        self.view.layoutIfNeeded()
      }
    }
    calendarView.scopeTransitionDebugHandler = { [weak self] snapshot in
      self?.trace(snapshot)
    }

    for labView in [titleLabel, calendarView, detailsLabel, statusLabel] {
      labView.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(labView)
    }

    calendarHeightConstraint = calendarView.heightAnchor.constraint(equalToConstant: 320)
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      titleLabel.heightAnchor.constraint(equalToConstant: 58),

      calendarView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
      calendarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      calendarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      calendarHeightConstraint,

      detailsLabel.topAnchor.constraint(equalTo: calendarView.bottomAnchor, constant: 14),
      detailsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      detailsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      detailsLabel.heightAnchor.constraint(equalToConstant: 92),

      statusLabel.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 14),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard !hasStarted, calendarView.bounds.width > 0 else { return }
    hasStarted = true

    calendarHeightConstraint.constant = calendarView.preferredHeight(
      forWidth: calendarView.bounds.width
    )
    view.layoutIfNeeded()
    statusLabel.text = "Automated cycle: month → week → month"
    print("SCOPE_LAB ready width=\(format(calendarView.bounds.width)) monthHeight=\(format(calendarView.bounds.height))")

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.runNextCycle()
    }
  }

  private func runNextCycle() {
    cycle += 1
    print("SCOPE_LAB action cycle=\(cycle) direction=month_to_week")
    calendarView.setScope(.week, anchoredAt: anchorDate, animated: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self else { return }
      print("SCOPE_LAB action cycle=\(self.cycle) direction=week_to_month")
      self.calendarView.setScope(.month, anchoredAt: self.anchorDate, animated: true)
    }

    if cycle < 3 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
        self?.runNextCycle()
      }
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
        self?.statusLabel.text = "Three deterministic cycles complete"
        print("SCOPE_LAB complete cycles=3")
      }
    }
  }

  private func makeContent() -> CalendarViewContent {
    let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    let endDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

    return CalendarViewContent(
      calendar: calendar,
      visibleDateRange: startDate...endDate,
      monthsLayout: .horizontal(
        options: HorizontalMonthsLayoutOptions(
          maximumFullyVisibleMonths: 1,
          scrollingBehavior: .paginatedScrolling(.init(
            restingPosition: .atLeadingEdgeOfEachMonth,
            restingAffinity: .atPositionsClosestToTargetOffset
          ))
        )
      )
    )
    .interMonthSpacing(18)
    .verticalDayMargin(4)
    .horizontalDayMargin(4)
    .monthHeaderItemProvider { _ in
      Color.clear
        .frame(height: 0)
        .calendarItemModel
    }
    .dayItemProvider { [calendar, anchorDate] day in
      var invariantViewProperties = DayView.InvariantViewProperties.baseInteractive
      let date = calendar.date(from: day.components)!
      if calendar.isDate(date, inSameDayAs: anchorDate) {
        invariantViewProperties.backgroundShapeDrawingConfig.fillColor = .systemBlue
      } else if day.day.isMultiple(of: 3) {
        invariantViewProperties.backgroundShapeDrawingConfig.fillColor =
          .systemGreen.withAlphaComponent(0.22)
      }

      return DayView.calendarItemModel(
        invariantViewProperties: invariantViewProperties,
        content: .init(
          dayText: "\(day.day)",
          accessibilityLabel: nil,
          accessibilityHint: nil
        )
      )
    }
  }

  private func traceHeightRequest(_ change: CalendarViewScopeHeightChange) {
    print(
      "SCOPE_HEIGHT scope=\(change.scope) target=\(format(change.height)) duration=\(format(change.animationDuration)) animated=\(change.animated) detailsModelY=\(format(detailsLabel.frame.minY)) detailsPresentationY=\(format(detailsLabel.layer.presentation()?.frame.minY ?? detailsLabel.frame.minY))"
    )
  }

  private func trace(_ snapshot: CalendarViewScopeTransitionDebugSnapshot) {
    let detailsPresentationFrame = detailsLabel.layer.presentation()?.frame ?? detailsLabel.frame
    let direction = "\(snapshot.fromScope)_to_\(snapshot.toScope)"
    print(
      "SCOPE_TRACE direction=\(direction) phase=\(snapshot.phase.rawValue) elapsed=\(format(snapshot.elapsedTime)) duration=\(format(snapshot.duration)) containerModelH=\(format(snapshot.containerBounds.height)) containerPresentationH=\(format(snapshot.containerPresentationFrame.height)) monthAnchorModelY=\(format(snapshot.monthAnchorFrame.midY)) monthAnchorPresentationY=\(format(snapshot.monthAnchorPresentationCenter.y)) weekAnchorY=\(format(snapshot.weekAnchorPresentationCenter.y)) clipModelY=\(format(snapshot.monthMaskFrame?.minY)) clipModelH=\(format(snapshot.monthMaskFrame?.height)) clipPresentationY=\(format(snapshot.monthMaskPresentationFrame?.minY)) clipPresentationH=\(format(snapshot.monthMaskPresentationFrame?.height)) backdropPresentationY=\(format(snapshot.transitionBackdropPresentationFrame?.minY)) backdropPresentationH=\(format(snapshot.transitionBackdropPresentationFrame?.height)) detailsModelY=\(format(detailsLabel.frame.minY)) detailsPresentationY=\(format(detailsPresentationFrame.minY))"
    )
  }

  private static func makeLabel(text: String, color: UIColor) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .headline)
    label.textColor = .white
    label.backgroundColor = color
    label.layer.cornerRadius = 16
    label.clipsToBounds = true
    return label
  }

  private func format(_ value: CGFloat?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.3f", value)
  }

  private func format(_ value: TimeInterval) -> String {
    String(format: "%.4f", value)
  }
}
