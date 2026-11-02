import SwiftUI

struct LabHomeView: View {
    @EnvironmentObject private var library: LabLibrary
    @EnvironmentObject private var artwork: LabArtwork
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selectedIndex: Int
    let onDetail: (LabBook) -> Void
    let onRead: (LabBook) -> Void
    let onReplay: () -> Void
    @State private var selectedGenre = "全部"

    private var book: LabBook { library.books[min(max(selectedIndex, 0), library.books.count - 1)] }
    private var animates: Bool { !reducedMotion && !library.minimizesMotion }
    private var visibleBooks: [LabBook] { selectedGenre == "全部" ? library.books : library.books.filter { $0.genre.contains(selectedGenre) } }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero(height: max(570, min(proxy.size.height * 0.87, 740)))
                    VStack(alignment: .leading, spacing: 28) {
                        sectionHeader("书架里的世界", caption: "离线灵感书库 · \(library.books.count) 本样本")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["全部", "小说", "本地", "图文"], id: \.self) { genre in
                                    Button { withAnimation(animates ? LabPalette.feedback : nil) { selectedGenre = genre } } label: {
                                        Text(genre).font(.subheadline.weight(selectedGenre == genre ? .semibold : .regular))
                                            .padding(.horizontal, 18).frame(minHeight: 44)
                                            .foregroundStyle(selectedGenre == genre ? LabPalette.midnight : .white.opacity(0.8))
                                            .background(selectedGenre == genre ? Color.white : Color.white.opacity(0.08), in: Capsule())
                                    }.buttonStyle(LabPressStyle())
                                }
                            }
                        }.padding(.top, -12)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 220), spacing: 16)], alignment: .leading, spacing: 24) {
                            ForEach(visibleBooks) { item in
                                Button { onDetail(item) } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        LabCover(book: item).aspectRatio(0.70, contentMode: .fit)
                                        Text(item.title).font(.headline).foregroundStyle(.white)
                                        Text(item.genre).font(.caption).foregroundStyle(.white.opacity(0.56))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(LabPressStyle())
                            }
                        }
                        invitation
                        Text("这是视觉实验书库，不连接书源或推荐服务。所有作品均为离线演示，不写入正式纸间。")
                            .font(.caption).lineSpacing(4).foregroundStyle(.white.opacity(0.5))
                    }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 120)
                }
            }
            .background(LabPalette.midnight)
            .coordinateSpace(name: "homeScroll")
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
    }

    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let offset = geometry.frame(in: .named("homeScroll")).minY
                ZStack {
                    if library.usesImmersiveBackground, let image = artwork.image(book.artwork) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height + max(offset, 0))
                            .offset(y: animates ? -offset * 0.18 : 0)
                    } else { LabPalette.midnight }
                    LinearGradient(stops: [.init(color: .black.opacity(0.18), location: 0),
                                           .init(color: .clear, location: 0.33),
                                           .init(color: LabPalette.midnight.opacity(0.55), location: 0.58),
                                           .init(color: LabPalette.midnight, location: 1)], startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [.black.opacity(0.23), .clear], startPoint: .top, endPoint: .center)
                }
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .id(book.id)
                .transition(.opacity)
            }.accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 160)
                HStack(spacing: 8) {
                    Capsule().fill(LabPalette.gold).frame(width: 20, height: 2)
                    Text("本期封面故事  /  \(String(format: "%02d", selectedIndex + 1))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                }.foregroundStyle(LabPalette.gold)
                Text(book.title)
                    .font(typeSize.isAccessibilitySize ? .system(.largeTitle, design: .serif).weight(.semibold) : .system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text("\(book.author)  ·  \(book.genre)  ·  原创演示")
                    .font(.caption).foregroundStyle(.white.opacity(0.72))
                Text(book.synopsis).font(.subheadline).lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.79)).lineLimit(typeSize.isAccessibilitySize ? 5 : 3)
                HStack(spacing: 12) {
                    Button { onRead(book) } label: {
                        Label(library.snapshot.positions[book.id] == nil ? "翻开这个故事" : "继续这段旅程", systemImage: "book.fill")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(LabPalette.midnight).background(.white, in: Capsule())
                    }.accessibilityIdentifier("home.read")
                    Button { onDetail(book) } label: {
                        Image(systemName: "arrow.up.right").font(.title3)
                            .frame(width: 50, height: 50).background(.white.opacity(0.13), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                    }.accessibilityLabel("查看\(book.title)简介").accessibilityIdentifier("home.detail")
                }.buttonStyle(LabPressStyle()).foregroundStyle(.white).padding(.top, 6)
                HStack {
                    HStack(spacing: 5) {
                        ForEach(library.books.indices, id: \.self) { index in
                            Capsule().fill(index == selectedIndex ? Color.white : .white.opacity(0.25))
                                .frame(width: index == selectedIndex ? 23 : 5, height: 4)
                        }
                    }.accessibilityLabel("封面 \(selectedIndex + 1)，共 \(library.books.count) 本")
                    Spacer()
                    Button { switchBook(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("上一张海报")
                    Button { switchBook(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("下一张海报")
                }.foregroundStyle(.white.opacity(0.8))
            }.padding(.horizontal, 26).padding(.bottom, 2)

            VStack {
                HStack {
                    HStack(spacing: 9) {
                        LabMark().scaleEffect(0.35).frame(width: 28, height: 32)
                        Text("纸间").font(.system(.title3, design: .serif).weight(.semibold)).tracking(3)
                    }
                    Spacer()
                    Button(action: onReplay) {
                        Image(systemName: "sparkles").font(.body).frame(width: 44, height: 44)
                            .background(.black.opacity(0.15), in: Circle())
                    }.accessibilityLabel("重播启动引导")
                }
                .foregroundStyle(.white).padding(.horizontal, 24).padding(.top, 64)
                Spacer()
            }
        }
        .frame(minHeight: height)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { gesture in
            guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.3 else { return }
            switchBook(gesture.translation.width < 0 ? 1 : -1)
        })
        .animation(animates ? .easeInOut(duration: 0.45) : nil, value: selectedIndex)
    }

    private var invitation: some View {
        Button(action: onReplay) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "sparkles.rectangle.stack").font(.title)
                VStack(alignment: .leading, spacing: 7) {
                    Text("再看一次序章").font(.headline)
                    Text("书海、藏书票与轨道，在指尖重新展开。")
                        .font(.caption).lineSpacing(4).foregroundStyle(.white.opacity(0.58))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }.padding(22).foregroundStyle(.white)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 0.7))
        }.buttonStyle(LabPressStyle())
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(.white)
                Text(caption).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "books.vertical").foregroundStyle(LabPalette.gold)
        }
    }

    private func switchBook(_ direction: Int) {
        guard let next = IntroChoreography.nextIndex(selectedIndex, direction: direction, count: library.books.count) else { return }
        withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { selectedIndex = next }
    }
}
