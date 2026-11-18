import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderAdditionalPageModesTests: XCTestCase {
    func testAdditionalModesHaveStableSettingsAndAnimationMappings() {
        let modes: [(ReaderMode, String, CoverPageTurnStyle)] = [
            (.verticalSlide, "纵向", .verticalSlide),
            (.parallax, "视差", .parallax),
            (.wipe, "擦除", .wipe),
            (.split, "对开", .split),
            (.perspective, "翻转", .perspective)
        ]

        for (mode, title, style) in modes {
            XCTAssertEqual(mode.title, title)
            XCTAssertEqual(mode.panTurnStyle, style)
            XCTAssertEqual(try? JSONDecoder().decode(ReaderMode.self, from: JSONEncoder().encode(mode)), mode)
        }
        XCTAssertEqual(Set(ReaderMode.allCases.map(\.title)).count, ReaderMode.allCases.count)
    }

    func testNewPageEffectsReachIntermediateStateInBothDirections() {
        let modes: [(ReaderMode, CoverPageTurnStyle)] = [
            (.verticalSlide, .verticalSlide), (.parallax, .parallax), (.wipe, .wipe),
            (.split, .split), (.perspective, .perspective)
        ]
        let width: CGFloat = 390
        let height: CGFloat = 844

        for (mode, style) in modes {
            for direction in [-1, 1] {
                let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
                let pages = (0..<3).map { _ in
                    let page = UIView(frame: container.bounds)
                    container.addSubview(page)
                    return page
                }
                let surface = ReaderPageRevealSurface()
                surface.prepare(direction: direction, style: style, in: container, pages: pages)
                let translation = CGFloat(-direction) * width / 2
                surface.apply(style: style, translation: translation,
                              in: container, pages: pages)
                let incoming = direction < 0 ? pages[0] : pages[2]
                XCTAssertFalse(incoming.isUserInteractionEnabled, "\(mode) must not expose a covered page to touch")
                XCTAssertTrue(incoming.accessibilityElementsHidden)

                switch mode {
                case .verticalSlide:
                    XCTAssertEqual(abs(pages[1].transform.ty), height / 2, accuracy: 1)
                    XCTAssertEqual(abs(incoming.transform.ty), height / 2, accuracy: 1)
                case .parallax:
                    XCTAssertEqual(abs(pages[1].transform.tx), width * 0.14, accuracy: 1)
                    XCTAssertEqual(abs(incoming.transform.tx), width / 2, accuracy: 1)
                case .wipe, .split:
                    XCTAssertNotNil(incoming.mask)
                    XCTAssertEqual(incoming.mask?.bounds.width ?? 0, width / 2, accuracy: 1)
                    let expectedCenter = style == .split ? width / 2 : width * (direction > 0 ? 0.75 : 0.25)
                    XCTAssertEqual(incoming.mask?.center.x ?? 0, expectedCenter, accuracy: 1)
                case .perspective:
                    XCTAssertNotEqual(pages[1].layer.transform.m34, 0)
                    XCTAssertGreaterThan(abs(pages[1].layer.transform.m13), 0.1)
                default:
                    XCTFail("Unexpected mode in this test")
                }
                surface.reset(pages: pages)
                XCTAssertNil(incoming.mask)
                XCTAssertEqual(incoming.transform, .identity)
                XCTAssertTrue(CATransform3DIsIdentity(incoming.layer.transform))
                XCTAssertTrue(incoming.isUserInteractionEnabled)
                XCTAssertFalse(incoming.accessibilityElementsHidden)
            }
        }
    }

    func testSwitchingMaskStyleRemasksTheSameNeighbour() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let current = UIView(frame: container.bounds)
        let next = UIView(frame: container.bounds)
        container.addSubview(current)
        container.addSubview(next)
        let pages: [UIView?] = [nil, current, next]
        let surface = ReaderPageRevealSurface()

        surface.apply(style: .wipe, translation: -130, in: container, pages: pages)
        let aperture = try XCTUnwrap(next.mask)
        surface.apply(style: .split, translation: -130, in: container, pages: pages)
        let split = try XCTUnwrap(next.mask)
        XCTAssertFalse(split === aperture)
        XCTAssertEqual(split.center.x, container.bounds.midX)
        surface.apply(style: .ripple, translation: -130, in: container, pages: pages)
        XCTAssertTrue(next.mask === aperture)
    }
}
