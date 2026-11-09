import SwiftUI

/// Reports how far the attached content sits above the top edge of a named
/// coordinate space. The raw offset travels as a preference, never as `@State`,
/// so a 120 Hz scroll does not re-evaluate the screen that owns it.
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Publishes the content's distance below the top edge of `space`; scrolling
    /// down makes the value more negative.
    func reportsScrollOffset(in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(space)).minY
                )
            }
        )
    }
}

extension View {
    /// iOS 18 feeds the gate from `onScrollGeometryChange`; emitting a
    /// preference as well would keep the per-frame layout walk alive.
    @ViewBuilder
    func reportsScrollOffsetWhenPreferenceIsUsed(in space: String) -> some View {
        if #available(iOS 18.0, *) {
            self
        } else {
            reportsScrollOffset(in: space)
        }
    }
}

/// Decides whether a scroll-collapsing navigation bar belongs on screen.
///
/// Two properties matter more than the thresholds themselves:
///
/// 1. It keeps its own offset history, so no intermediate offset ever reaches
///    SwiftUI state. A per-frame `@State` write here would re-evaluate the whole
///    shelf body on every frame — the exact cost this screen already paid for.
/// 2. Collapse and reveal use different thresholds. Hiding the bar changes the
///    safe area, which feeds a new offset straight back in; without the gap the
///    bar would oscillate at the boundary.
final class ScrollChromeGate {
    /// Scrolled-down distance after which the bar leaves.
    var hideAfter: CGFloat = 240
    /// Upward travel that brings the bar back, matching a familiar browser feel.
    var revealOnUpward: CGFloat = 24

    private var lastTravelled: CGFloat?
    private(set) var isCollapsed = false

    func update(offset: CGFloat, onChange: (Bool) -> Void) {
        let travelled = -offset
        defer { lastTravelled = travelled }

        if isCollapsed {
            if travelled <= 0 {
                isCollapsed = false
                onChange(false)
                return
            }
            guard let lastTravelled else { return }
            let delta = travelled - lastTravelled
            if delta < -revealOnUpward {
                isCollapsed = false
                onChange(false)
            }
        } else if travelled > hideAfter {
            isCollapsed = true
            onChange(true)
        }
    }

    /// Used when navigation or a refresh moves the content without a scroll.
    func reset() {
        lastTravelled = nil
        isCollapsed = false
    }
}

extension View {
    /// Feeds a named scroll container into `gate` and applies the resulting bar
    /// visibility. `gate` owns the history; `collapsed` is only written when the
    /// answer flips.
    func collapsingNavigationBar(
        in space: String,
        gate: ScrollChromeGate,
        collapsed: Binding<Bool>
    ) -> some View {
        coordinateSpace(name: space)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                gate.update(offset: offset) { shouldCollapse in
                    guard collapsed.wrappedValue != shouldCollapse else { return }
                    // Hiding the bar changes the safe area. Animating that
                    // change spends 0.18 s re-laying out the whole shelf at
                    // exactly the scroll position the user is dragging
                    // through; flip it in one frame instead.
                    collapsed.wrappedValue = shouldCollapse
                }
            }
    }

    /// iOS 18 reads the scroll geometry directly. The preference channel still
    /// exists for iOS 16/17, but it makes every scroll frame walk a layout pass
    /// through the whole screen; at 120 Hz that alone costs a visible chunk of
    /// the frame budget and keeps the bar's 240 pt threshold feeling like a
    /// hitch. Prefer the native channel whenever it is available.
    @ViewBuilder
    func collapsingNavigationBarModern(
        in space: String,
        gate: ScrollChromeGate,
        collapsed: Binding<Bool>
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, travelled in
                gate.update(offset: -travelled) { shouldCollapse in
                    guard collapsed.wrappedValue != shouldCollapse else { return }
                    collapsed.wrappedValue = shouldCollapse
                }
            }
        } else {
            collapsingNavigationBar(in: space, gate: gate, collapsed: collapsed)
        }
    }

    /// Applies navigation-bar visibility from a collapse flag.
    func scrollCollapsedNavigationBar(_ collapsed: Bool) -> some View {
        toolbar(collapsed ? .hidden : .visible, for: .navigationBar)
    }
}
