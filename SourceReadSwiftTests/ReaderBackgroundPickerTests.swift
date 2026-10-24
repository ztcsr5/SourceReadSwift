import XCTest
@testable import SourceReadSwift

/// #8 的回归锁：外观面板里不能再出现「名字不同、颜色一样」的主题。
/// 老用户存下来的 rawValue（含已从面板收起的 sakuraInk 等）必须仍然能解码，
/// 所以这里同时校验「picker 收敛」与「全量解码兼容」两件事。
final class ReaderBackgroundPickerTests: XCTestCase {

    func testPickerHidesVisuallyIdenticalThemes() {
        // 素白/水墨屏/大地/墨白 底色都是 #FFFFFF；浅灰与樱白差 7 阶；极黑与深渊几乎一致。
        let cases = ReaderBackground.pickerCases
        var seen: [String: String] = [:]
        for item in cases {
            let key = "\(item.dayBackgroundHex)-\(item.dayTextHex)"
            if let existing = seen[key] {
                XCTFail("\(item.rawValue) 与 \(existing) 在白天下完全同色（\(key)），不该同时出现在面板里")
            }
            seen[key] = item.rawValue
        }
        XCTAssertEqual(cases.count, 11, "面板主题数应为 11")
    }

    func testPickerCasesAreSubsetOfAllCases() {
        let all = Set(ReaderBackground.allCases.map(\.rawValue))
        for item in ReaderBackground.pickerCases {
            XCTAssertTrue(all.contains(item.rawValue), "\(item.rawValue) 不在 allCases 里")
        }
    }

    func testPickerHasNoDuplicates() {
        let values = ReaderBackground.pickerCases.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testHiddenThemesStillDecodeFromStoredValue() {
        // 这些已从面板收起，但用户老设置里可能还存着；解码必须成功、必须还能上色。
        for raw in ["eink", "sakuraInk", "sakuraEarthly", "sakuraClassic", "sakuraVader"] {
            guard let theme = ReaderBackground(rawValue: raw) else {
                XCTFail("\(raw) 解码失败，老设置会丢")
                continue
            }
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertNotEqual(theme.dayBackgroundHex, 0, "\(raw) 没有白天底色")
        }
    }

    func testCustomThemeStaysSelectable() {
        XCTAssertTrue(ReaderBackground.pickerCases.contains(.custom))
    }
}
