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

import CoreGraphics
import Foundation

/// The amount of calendar content presented by a ``CalendarScopeView``.
public enum CalendarViewScope: Hashable {

  /// Displays complete months using HorizonCalendar's existing month renderer.
  case month

  /// Displays one horizontally paged week at a time.
  case week
}

/// Describes a preferred-height change requested by a ``CalendarScopeView``.
public struct CalendarViewScopeHeightChange {

  /// The scope whose content determines `height`.
  public let scope: CalendarViewScope

  /// The preferred container height for the scope.
  public let height: CGFloat

  /// The duration the calendar uses for its matching visual transition.
  public let animationDuration: TimeInterval

  /// Whether the height change should be animated.
  public let animated: Bool
}

/// Per-frame geometry emitted while a calendar scope transition is running.
///
/// This API is intended for animation diagnostics and automated visual labs.
@_spi(Instrumentation)
public struct CalendarViewScopeTransitionDebugSnapshot {

  public enum Phase: String {
    case started
    case running
    case completed
  }

  public let phase: Phase
  public let fromScope: CalendarViewScope
  public let toScope: CalendarViewScope
  public let elapsedTime: TimeInterval
  public let duration: TimeInterval
  public let containerBounds: CGRect
  public let containerPresentationFrame: CGRect
  public let monthFrame: CGRect
  public let monthPresentationFrame: CGRect
  public let monthTransform: CGAffineTransform
  public let monthPresentationTransform: CGAffineTransform
  public let weekFrame: CGRect
  public let weekPresentationFrame: CGRect
  public let monthMaskFrame: CGRect?
  public let monthMaskPresentationFrame: CGRect?
  public let transitionBackdropFrame: CGRect?
  public let transitionBackdropPresentationFrame: CGRect?
  public let matchedRowFrame: CGRect?
  public let matchedRowPresentationFrame: CGRect?
  public let monthAnchorFrame: CGRect
  public let weekAnchorFrame: CGRect
  public let monthAnchorPresentationCenter: CGPoint
  public let weekAnchorPresentationCenter: CGPoint
}
