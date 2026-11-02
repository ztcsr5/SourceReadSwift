import Foundation

/// Real book metadata with explicitly original interaction-only sample passages.
struct LabBook: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let artwork: String
    let genre: String
    let tagline: String
    let synopsis: String

    var chapters: [String] { ["样段一 · 翻开书页", "样段二 · 让阅读继续", "样段三 · 留下片刻"] }

    var paragraphs: [String] {
        ["这里是《\(title)》的阅读器交互体验页。以下文字由纸间自行编写，用于演示排版与定位，不是原书正文。",
         "一本书的封面只是入口。真正让人停留的，是翻开之后的某一行字，是愿意在忙碌生活中留给自己的片刻。",
         "风吹动窗边的书页。你可以调大字号，翻到下一段，也可以把这一句留成书笺；下次打开时，从停下的地方继续。",
         "每一次读到这里，都可以按下“记到这里”。位置会保存在这个独立测试 App 内，不会写入正式纸间的阅读记录。",
         "这张书笺来自你刚刚点击的实际段落，而不是预先播放的画面。返回首页、重新进入阅读器，保存的内容仍然在这里。"]
    }

    static let samples: [LabBook] = [
        .init(id: "threebody", title: "三体", author: "刘慈欣", artwork: "BookThreeBody", genre: "科幻 · 小说",
              tagline: "把目光，从书页投向星空。", synopsis: "一场横跨文明与宇宙的故事，从人类发出的一次呼唤开始。个人的选择与文明的命运交织，让遥远星空成为切近的疑问。这里仅提供交互样段，不含原书正文。"),
        .init(id: "dune", title: "沙丘", author: "弗兰克·赫伯特", artwork: "BookDune", genre: "科幻 · 小说",
              tagline: "穿过沙海，走进另一个世界。", synopsis: "在沙漠星球厄拉科斯，权力、生态与人的命运紧密相连。一位年轻人的旅程，牵动了庞大帝国的未来。本页简介为实验编写。"),
        .init(id: "prince", title: "小王子", author: "安托万·德·圣埃克苏佩里", artwork: "BookPrince", genre: "童话 · 图文",
              tagline: "为一朵花，重新认识整个世界。", synopsis: "从一颗小小的星球出发，小王子在旅途中遇见不同的人，也重新理解陪伴与牵挂。这是一本可以在不同年纪重新翻开的书。"),
        .init(id: "hobbit", title: "霍比特人", author: "J. R. R. 托尔金", artwork: "BookHobbit", genre: "奇幻 · 小说",
              tagline: "一扇家门之外，就是远方。", synopsis: "安静的生活被一次意外来访打断。比尔博踏上离家很远的旅程，在山川、谜题和未知之间，发现从前未曾认识的自己。"),
        .init(id: "potter", title: "哈利·波特与魔法石", author: "J. K. 罗琳", artwork: "BookPotter", genre: "奇幻 · 小说",
              tagline: "等待你的，也许是另一种日常。", synopsis: "一封来信打开了哈利从未想过的世界。魔法学校里的友谊、秘密与冒险，让平凡日子有了不同的方向。"),
        .init(id: "1984", title: "1984", author: "乔治·奥威尔", artwork: "Book1984", genre: "文学 · 本地",
              tagline: "在文字之间，保留自己的目光。", synopsis: "一部围绕权力、语言与个体展开的小说。温斯顿的生活让读者思考：记忆、表达与自由，如何影响一个人对世界的理解。"),
        .init(id: "hitchhiker", title: "银河系漫游指南", author: "道格拉斯·亚当斯", artwork: "BookHitchhiker", genre: "科幻 · 小说",
              tagline: "别慌，宇宙还很大。", synopsis: "一次突如其来的宇宙旅行，把阿瑟带离熟悉的生活。荒诞的想象与幽默相遇，让宏大的宇宙问题有了轻盈的入口。")
    ]
}

struct LabPosition: Codable, Equatable {
    var chapter = 0
    var paragraph = 0
}

struct LabQuote: Codable, Identifiable, Equatable {
    let id: UUID
    let bookID: String
    let bookTitle: String
    let text: String
    let createdAt: Date
}

struct LabSnapshot: Codable, Equatable {
    var positions: [String: LabPosition] = [:]
    var quotes: [LabQuote] = []
}

/// The intro's normalized poses keep a single set of cover identities across scenes.
enum IntroChoreography {
    static let stepCount = 6

    static func safeStep(_ proposed: Int) -> Int { min(max(proposed, 0), stepCount - 1) }

    static func nextIndex(_ index: Int, direction: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let shift = direction % count
        return ((index % count + shift) % count + count) % count
    }
}
