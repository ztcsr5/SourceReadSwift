import SwiftUI

struct LabIntroView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var step: Int
    let onFinish: () -> Void
    var sampledTime: Double? = nil
    @State private var droppedCount = 0

    private var animates: Bool { !reducedMotion && !library.minimizesMotion && scenePhase == .active }
    private let titles = ["世界，正在翻开。", "让喜欢，各就其位。", "把一瞬，藏进纸间。", "故事，不止一种形状。", "下一页，属于你。"]
    private let subtitles = ["穿过书页与星光，遇见值得停留的故事。", "从散落的灵感，到一座有序的私人藏书室。", "一张藏书票，收好每一次心动。", "让不同的阅读方式，在同一个世界相遇。", "封面之外，还有一个世界等你走进去。"]

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 650 || typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                header.padding(.horizontal, 24).padding(.top, 12)
                ZStack {
                    IntroPosterField(step: step, isAnimated: animates && step < 2, sampledTime: sampledTime)
                        .opacity(step < 2 ? 1 : 0)
                    if step == 2 { tickets.transition(.opacity.combined(with: .scale(scale: 0.9))) }
                    if step == 3 { IntroOrbit(isAnimated: animates, sampledTime: sampledTime).transition(.opacity.combined(with: .scale(scale: 0.8))) }
                    if step == 4 { portal.transition(.scale(scale: 0.86).combined(with: .opacity)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped().padding(.vertical, compact ? 8 : 16)

                VStack(spacing: compact ? 12 : 16) {
                    VStack(spacing: 10) {
                        Text(titles[IntroChoreography.safeStep(step)])
                            .font(.system(compact ? .title2 : .title, design: .serif).weight(.semibold))
                            .contentTransition(.opacity)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitles[IntroChoreography.safeStep(step)])
                            .font(.subheadline).foregroundStyle(LabPalette.ink.opacity(0.65))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<IntroChoreography.stepCount, id: \.self) { index in
                            Capsule().fill(step == index ? LabPalette.accent : LabPalette.accent.opacity(0.18))
                                .frame(width: step == index ? 22 : 5, height: 5)
                        }
                    }.accessibilityLabel("引导第 \(step + 1) 步，共 5 步")
                    Button(action: advance) {
                        HStack {
                            Spacer()
                            Text(step == 4 ? "翻开纸间" : "继续").font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 22).frame(minHeight: 54)
                        .foregroundStyle(.white).background(LabPalette.ink, in: Capsule())
                    }.buttonStyle(LabPressStyle()).accessibilityIdentifier("intro.continue")
                    Text("动效实验 · 全部内容为原创离线样本")
                        .font(.system(size: 10)).foregroundStyle(LabPalette.ink.opacity(0.5))
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
        }
        .foregroundStyle(LabPalette.ink)
        .background {
            ZStack {
                LabPalette.paper
                RadialGradient(colors: [Color(red: 0.85, green: 0.78, blue: 0.95).opacity(0.6), .clear],
                               center: .topLeading, startRadius: 1, endRadius: 600)
                RadialGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.78).opacity(0.4), .clear],
                               center: .bottomTrailing, startRadius: 1, endRadius: 450)
            }.ignoresSafeArea()
        }
        .animation(animates ? LabPalette.navigation : nil, value: step)
        .task(id: "\(step)-\(animates)") {
            guard step == 2 else { return }
            droppedCount = sampledTime != nil || !animates ? 3 : 0
            guard animates, sampledTime == nil else { return }
            for count in 1...3 {
                do { try await Task.sleep(nanoseconds: UInt64(count == 1 ? 200_000_000 : 300_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.62, dampingFraction: 0.76)) { droppedCount = count }
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "book.pages").font(.caption)
                Text("纸间  /  PROLOGUE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
            }
            Spacer()
            Button("跳过", action: onFinish).font(.subheadline).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("intro.skip")
        }
    }

    private var tickets: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 48, 340)
            ZStack {
                Capsule().fill(LabPalette.ink.opacity(0.15)).frame(width: width * 0.72, height: 7)
                    .position(x: proxy.size.width / 2, y: 24)
                ForEach(0..<3, id: \.self) { index in
                    LabTicket(book: LabBook.samples[index], serial: String(format: "%02d", index + 1))
                        .frame(width: width)
                        .rotationEffect(.degrees(Double(index - 1) * 5))
                        .scaleEffect(1 - CGFloat(index) * 0.035)
                        .offset(y: droppedCount > index ? CGFloat(index * 55) : -380)
                        .opacity(droppedCount > index ? 1 : 0)
                        .zIndex(Double(3 - index))
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("三张原创藏书票从应用内书笺出口依次落下")
    }

    private var portal: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                LabCover(book: LabBook.samples[0], showsTitle: false, radius: 24)
                LinearGradient(colors: [.clear, LabPalette.midnight.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text("从这一页开始").font(.caption).tracking(3)
                    Text("潮汐之门").font(.system(.largeTitle, design: .serif).weight(.semibold))
                    Text("海上的门亮了，故事也开始了。").font(.subheadline)
                }.foregroundStyle(.white).padding(24)
            }
            .frame(width: min(proxy.size.width - 64, 340), height: max(proxy.size.height - 12, 80))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .rotation3DEffect(.degrees(animates ? -4 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: LabPalette.midnight.opacity(0.25), radius: 24, x: 10, y: 12)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }.accessibilityHidden(true)
    }

    private func advance() {
        if step >= 4 { onFinish() }
        else { step = IntroChoreography.safeStep(step + 1) }
    }
}
