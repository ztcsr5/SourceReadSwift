import Foundation

/// Original offline fiction; these records never enter the production bookshelf.
struct LabBook: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let artwork: String
    let genre: String
    let tagline: String
    let synopsis: String

    var chapters: [String] { ["第一章 · 风带来的信", "第二章 · 潮汐之外", "第三章 · 尚未抵达的明天"] }

    var paragraphs: [String] {
        ["午夜，城市的灯光一盏一盏熄灭，海上的那道门却亮了起来。她停在最后一级石阶前，听见风翻动纸页的声音。",
         "信封里没有署名，只有一张画着星辰的地图。地图的边缘留着一行小字：有些远方，必须亲自翻开。",
         "她把那句话念了两遍，收进口袋。潮水掠过脚边，像是另一个世界递来的邀请。",
         "晨光缓缓落在旧书的扉页。她终于知道，故事从来不是答案，而是通往答案的另一扇门。",
         "这是《\(title)》的原创离线演示片段。你可以试读、翻章、保存书笺；不会修改正式纸间的书架或阅读位置。"]
    }

    static let samples: [LabBook] = [
        .init(id: "tide", title: "潮汐之门", author: "闻屿", artwork: "Ref106379", genre: "奇境 · 小说",
              tagline: "在故事的另一边，遇见自己。", synopsis: "每逢满月，海上会升起一座通往失落图书馆的门。年轻的修书师收到一封来自明天的信，循着潮汐走向那扇门。她不知道，那里收藏的不是书，而是每个人未曾选择的人生。"),
        .init(id: "mist", title: "雾都遗信", author: "林时雨", artwork: "CoverMisty", genre: "悬疑 · 小说",
              tagline: "没有寄出的信，终会找到你。", synopsis: "在终年起雾的城里，未寄出的信件会在午夜找到收信人。她收到一封写着明天日期的来信，从此开始寻找那条地图上不存在的街。"),
        .init(id: "sea", title: "海边失眠者", author: "陆遥", artwork: "CoverSea", genre: "治愈 · 本地",
              tagline: "把忙碌留在岸上。", synopsis: "离开城市后的第一个夏天，她在海边开了一间只在深夜营业的小书店。每个人都把秘密留在书页里，而潮水总能带来新的故事。"),
        .init(id: "star", title: "星河折叠", author: "宋见川", artwork: "CoverStar", genre: "科幻 · 小说",
              tagline: "每颗星，都是未完的故事。", synopsis: "宇宙被折成一封信。一位孤独的领航员，在返航信标消失之前，决定把它送回地球。"),
        .init(id: "arch", title: "遗迹之门", author: "陈风", artwork: "CoverArchaeology", genre: "冒险 · 小说",
              tagline: "答案，藏在最后一道门后。", synopsis: "一封来自旧时代的密信指向一座失落遗迹。年轻研究者走入雨林，发现所有地图都在隐瞒同一个秘密。"),
        .init(id: "mountain", title: "山雨入梦", author: "闻溪", artwork: "CoverMountain", genre: "幻想 · 图文",
              tagline: "山中无日月，书里有光阴。", synopsis: "少年循着古老歌谣走进群山，在云雨之间，看见另一个未被记载的世界。本实验只提供文字试读，不冒充漫画引擎。"),
        .init(id: "letter", title: "荒原来信", author: "岑末", artwork: "CoverLetter", genre: "旅途 · 小说",
              tagline: "风经过时，故事有了声音。", synopsis: "一位邮差穿过荒原，把无法寄达的信交给每一个等待过的人。漫长的路上，时间忽然有了形状。")
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
