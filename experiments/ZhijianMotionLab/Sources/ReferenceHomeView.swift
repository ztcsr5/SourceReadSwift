import SwiftUI

struct ReferenceHomeView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Binding var selectedIndex: Int
    let onDetail: (ReferenceMedia) -> Void
    private let heroes = [106379, 157336, 110356, 87739, 496243, 603, 823219, 277834]
    private let canvas = Color(red: 0.17, green: 0.10, blue: 0.075)

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TabView(selection: $selectedIndex) {
                        ForEach(heroes.indices, id: \.self) { index in
                            hero(ReferenceMedia.item(heroes[index]), height: proxy.size.height * 0.72)
                                .tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: max(480, proxy.size.height * 0.72))
                    HStack(spacing: 6) {
                        ForEach(heroes.indices, id: \.self) { index in
                            Circle().fill(.white.opacity(index == selectedIndex ? 1 : 0.25)).frame(width: index == selectedIndex ? 7 : 5, height: index == selectedIndex ? 7 : 5)
                        }
                    }.padding(.top, 4).padding(.bottom, 22)
                    posterRow("正在热映", ids: [277834, 560057, 823219, 508943, 475557])
                    posterRow("正在播出", ids: [106379, 110356, 1416, 71712, 60573])
                    posterRow("本周趋势", ids: [157336, 496243, 87739, 603, 240])
                    Text("私人视觉对照 · 离线片目，不提供播放或实时榜单")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5)).padding(24)
                }.padding(.bottom, 100)
            }.background(canvas).ignoresSafeArea(edges: .top)
        }.preferredColorScheme(.dark)
    }

    private func hero(_ item: ReferenceMedia, height: CGFloat) -> some View {
        Button { onDetail(item) } label: {
            ZStack(alignment: .bottom) {
                ReferenceImage(name: item.poster)
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: canvas.opacity(0.3), location: 0.64), .init(color: canvas, location: 1)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 9) {
                    if !item.logo.isEmpty {
                        ReferenceImage(name: item.logo, fits: true).frame(height: 92).padding(.horizontal, 50)
                    } else { Text(item.title).font(.system(size: 36, weight: .bold, design: .serif)) }
                    Text("\(item.genre)  ·  \(item.release)").font(.system(size: 13, weight: .medium))
                    Text(item.overview).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                    HStack(spacing: 5) {
                        Text("TMDB").font(.system(size: 6, weight: .black)).foregroundStyle(.cyan)
                        Text(item.rating).font(.system(size: 11, weight: .medium))
                    }
                }.foregroundStyle(.white).padding(.horizontal, 22).padding(.bottom, 12)
            }.frame(height: max(height, 480)).clipped()
        }.buttonStyle(.plain).accessibilityLabel("查看\(item.title)简介").accessibilityIdentifier("home.detail")
    }

    private func posterRow(_ title: String, ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 18, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }.padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ids, id: \.self) { id in
                        let item = ReferenceMedia.item(id)
                        Button { onDetail(item) } label: {
                            VStack(spacing: 5) {
                                ReferencePoster(item: item).frame(width: 108, height: 162)
                                Text(item.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                Text(item.year).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                            }.frame(width: 108)
                        }.buttonStyle(LabPressStyle())
                    }
                }.padding(.horizontal, 14)
            }
        }.foregroundStyle(.white).padding(.bottom, 24)
    }
}

struct ReferenceDetailView: View {
    @EnvironmentObject private var shelf: ReferenceShelf
    @Environment(\.dismiss) private var dismiss
    let item: ReferenceMedia
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReferenceImage(name: item.backdrop).frame(height: 270).clipped()
                    .overlay(alignment: .topLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
                            .padding(.leading, 16).padding(.top, 54).accessibilityLabel("返回首页").accessibilityIdentifier("detail.back")
                    }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        ReferencePoster(item: item).frame(width: 85, height: 128)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(item.title).font(.title2.bold())
                            Text("\(item.year) · \(item.genre)").font(.subheadline).foregroundStyle(.secondary)
                            Text("TMDB  \(item.rating)").font(.headline)
                        }
                    }
                    Button { shelf.toggle(item) } label: {
                        Label(shelf.saved.contains(item.id) ? "已加入待看" : "加入待看", systemImage: shelf.saved.contains(item.id) ? "checkmark" : "plus")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(.white).background(.blue, in: Capsule())
                    }.accessibilityIdentifier("detail.save")
                    Text("剧情简介").font(.title3.bold())
                    Text(item.overview).lineSpacing(7)
                    Text("离线界面测试，未接入播放服务。片目与评分来自安装包内的 TMDB 样本，并非实时数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.bottom, 40)
            }
        }.ignoresSafeArea(edges: .top).background(LabPalette.paper)
            .toolbar(.hidden, for: .navigationBar)
    }
}

struct ReferenceShelfView: View {
    @EnvironmentObject private var shelf: ReferenceShelf
    let onDetail: (ReferenceMedia) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("我的待看").font(.largeTitle.bold())
                if shelf.saved.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "ticket").font(.system(size: 48))
                        Text("还没有待看的作品").font(.headline)
                        Text("在发现页打开简介，点击“加入待看”。").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(ReferenceMedia.samples.filter { shelf.saved.contains($0.id) }) { item in
                    Button { onDetail(item) } label: { ReferenceTicket(item: item).frame(height: 128) }.buttonStyle(LabPressStyle()).accessibilityIdentifier("shelf.item.\(item.id)")
                }
            }.padding(22).padding(.bottom, 110)
        }.background(LabPalette.paper)
    }
}

struct ReferenceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onDetail: (ReferenceMedia) -> Void
    private var matches: [ReferenceMedia] { ReferenceMedia.samples.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List(matches) { item in
                Button { dismiss(); onDetail(item) } label: {
                    HStack(spacing: 14) {
                        ReferencePoster(item: item).frame(width: 40, height: 60)
                        VStack(alignment: .leading, spacing: 5) { Text(item.title); Text(item.year).font(.caption).foregroundStyle(.secondary) }
                    }.foregroundStyle(.primary)
                }
            }.searchable(text: $query, prompt: "搜索离线样本")
                .overlay { if matches.isEmpty { Text("没有匹配的离线片目").foregroundStyle(.secondary) } }
                .navigationTitle("搜索")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("离线片目").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 20).background(LabPalette.paper)
        }
    }
}
