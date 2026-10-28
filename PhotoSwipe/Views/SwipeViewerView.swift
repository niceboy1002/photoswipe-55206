import SwiftUI
import Photos
import UIKit

struct SwipeViewerView: View {
    let category: SmartCategory

    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var loading = true
    @State private var index = 0

    /// 整个横向内容被拖走了多少点。scrollX = index * 页宽 时正好停在第 index 张。
    /// 手指移动多少，画面就跟多少，松手后再吸附到最近的整数页。
    @State private var scrollX: CGFloat = 0
    /// 当前卡片纵向位移（上滑待删 / 下滑喜欢）
    @State private var dragY: CGFloat = 0
    /// 手势开始时的 scrollX，用来做增量计算
    @State private var startX: CGFloat = 0
    @State private var axis: DragAxis?
    @State private var animating = false

    @State private var toast: String?
    @State private var showTrash = false
    @State private var video: VideoSelection?

    private enum DragAxis { case horizontal, vertical }

    private struct VideoSelection: Identifiable {
        let id = UUID()
        let asset: PHAsset
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            stage

            VStack {
                topBar
                Spacer()
            }

            VStack {
                Spacer()
                bottomBar
            }

            toastLayer
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await loadList() }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .fullScreenCover(item: $video) { selection in
            VideoPlayerView(asset: selection.asset)
        }
        .onDisappear {
            library.stopPreheat()
        }
    }

    // MARK: - 主体

    private var stage: some View {
        GeometryReader { geo in
            let pageW = max(geo.size.width, 1)
            let cardW = max(geo.size.width - 26, 80)
            let cardH = max(geo.size.height, 80)

            ZStack {
                if loading {
                    ProgressView().tint(.white.opacity(0.5))
                } else if assets.isEmpty {
                    emptyState
                } else {
                    pager(pageW: pageW, cardW: cardW, cardH: cardH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(pageW: pageW, cardH: cardH))
        }
        .padding(.top, 58)
        .padding(.bottom, 84)
    }

    private func pager(pageW: CGFloat, cardW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            ForEach(visibleIndices(pageW: pageW), id: \.self) { i in
                cardView(i: i, pageW: pageW, cardW: cardW, cardH: cardH)
            }

            verticalFeedback(cardH: cardH)
                .allowsHitTesting(false)
        }
    }

    private func cardView(i: Int, pageW: CGFloat, cardW: CGFloat, cardH: CGFloat) -> some View {
        let x = CGFloat(i) * pageW - scrollX
        let fade = Double(min(abs(x) / pageW, 1))

        PhotoCard(asset: assets[i], onPlay: playAction(for: i))
            .frame(width: cardW, height: cardH)
            .scaleEffect(1 - CGFloat(fade) * 0.06)
            .opacity(1 - fade * 0.45)
            .offset(x: x, y: i == index ? dragY : 0)
            .zIndex(Double(1000 - abs(x)))
            .allowsHitTesting(i == index)
    }

    /// 只有视频才给点击回调
    private func playAction(for i: Int) -> (() -> Void)? {
        guard i >= 0, i < assets.count, assets[i].mediaType == .video else { return nil }
        let item = assets[i]
        return { video = VideoSelection(asset: item) }
    }

    /// 只渲染当前页和左右相邻页，几千张也不会卡
    private func visibleIndices(pageW: CGFloat) -> [Int] {
        guard !assets.isEmpty else { return [] }
        let current = Int(floor(scrollX / pageW))
        let low = max(0, current - 1)
        let high = min(assets.count - 1, current + 1)
        guard low <= high else { return [] }
        return Array(low...high)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(category == .all ? "全部看完了" : "这个分类处理完了")
                .font(.system(size: 16, weight: .semibold))
            Text("已标记的照片都在右上角的垃圾桶里")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(progressText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                showTrash = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())

                    if pending.count > 0 {
                        Text("\(pending.count)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
            }
            .disabled(pending.isEmpty)
            .opacity(pending.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var progressText: String {
        guard !assets.isEmpty else { return "0" }
        return "\(index + 1) / \(assets.count)"
    }

    // MARK: - 底部提示

    private var bottomBar: some View {
        HStack(spacing: 26) {
            hint(icon: "arrow.left.arrow.right", text: "滑动切换")
            hint(icon: "arrow.up", text: "待删")
            hint(icon: "arrow.down", text: "喜欢")
        }
        .padding(.bottom, 28)
        .opacity(0.55)
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundStyle(.white)
    }

    // MARK: - 拖动时的方向反馈

    @ViewBuilder
    private func verticalFeedback(cardH: CGFloat) -> some View {
        if dragY < -28 {
            feedbackBadge(symbol: "trash.fill",
                          text: "加入待删",
                          tint: .red,
                          progress: min(-dragY / (cardH * 0.32), 1))
        } else if dragY > 28 {
            feedbackBadge(symbol: "heart.fill",
                          text: "加入喜欢",
                          tint: .pink,
                          progress: min(dragY / (cardH * 0.32), 1))
        }
    }

    private func feedbackBadge(symbol: String, text: String, tint: Color, progress: CGFloat) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(width: 130, height: 130)
        .background(tint.opacity(0.85), in: Circle())
        .shadow(color: tint.opacity(0.4), radius: 24)
        .opacity(Double(progress))
        .scaleEffect(0.72 + progress * 0.28)
    }

    // MARK: - 手势

    private func dragGesture(pageW: CGFloat, cardH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !animating, !assets.isEmpty else { return }

                if axis == nil {
                    let t = value.translation
                    guard abs(t.width) > 7 || abs(t.height) > 7 else { return }
                    // 横向判定比纵向严格一点，斜着划不会误翻页
                    if abs(t.width) > abs(t.height) * 1.15 {
                        axis = .horizontal
                        startX = scrollX
                    } else {
                        axis = .vertical
                    }
                }

                switch axis {
                case .some(.horizontal):
                    // 手指向左 → scrollX 增大（内容左移，右邻页进来）
                    scrollX = rubber(startX - value.translation.width, pageW: pageW)
                case .some(.vertical):
                    dragY = value.translation.height
                case .none:
                    break
                }
            }
            .onEnded { value in
                guard !animating, !assets.isEmpty else { axis = nil; return }

                switch axis {
                case .some(.horizontal):
                    settle(value, pageW: pageW)
                case .some(.vertical):
                    let threshold = max(cardH * 0.12, 72)
                    if value.translation.height < -threshold {
                        markForDeletion(pageW: pageW, cardH: cardH)
                    } else if value.translation.height > threshold {
                        addToFavorites(pageW: pageW)
                    } else {
                        snapBack()
                    }
                case .none:
                    break
                }
                axis = nil
            }
    }

    /// 到边界时的橡皮筋阻尼，手感和系统相册一致
    private func rubber(_ x: CGFloat, pageW: CGFloat) -> CGFloat {
        let maxX = CGFloat(max(assets.count - 1, 0)) * pageW
        if x < 0 { return x * 0.32 }
        if x > maxX { return maxX + (x - maxX) * 0.32 }
        return x
    }

    /// 松手后吸附到最近的页。带速度预测，轻轻一甩也能翻过去。
    private func settle(_ value: DragGesture.Value, pageW: CGFloat) {
        let startPage = Int((startX / pageW).rounded())
        let projected = -value.predictedEndTranslation.width / pageW
        var target = startPage + Int(projected.rounded())

        // 甩得慢但拖得远，也算翻页
        if target == startPage, abs(value.translation.width) > pageW * 0.18 {
            target += value.translation.width < 0 ? 1 : -1
        }

        // 一次手势最多翻两页，避免一下甩过好几张
        target = min(max(target, startPage - 2), startPage + 2)
        target = min(max(target, 0), max(assets.count - 1, 0))

        if target != startPage { haptic() }

        animating = true
        index = target
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
            scrollX = CGFloat(target) * pageW
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            scrollX = CGFloat(target) * pageW
            animating = false
            preheat(pageW: pageW)
        }
    }

    private func snapBack() {
        animating = true
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            dragY = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            animating = false
        }
    }

    // MARK: - 三种动作

    /// 上滑：加入待删队列（不删除、不打断、不弹窗）
    private func markForDeletion(pageW: CGFloat, cardH: CGFloat) {
        guard index < assets.count else { return }
        let asset = assets[index]

        animating = true
        haptic(style: .medium)
        pending.add(asset.localIdentifier)

        withAnimation(.easeIn(duration: 0.26)) {
            dragY = -(cardH * 1.35)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            dragY = 0
            if index < assets.count {
                assets.remove(at: index)
            }
            if assets.isEmpty {
                index = 0
                scrollX = 0
            } else if index >= assets.count {
                index = assets.count - 1
                scrollX = CGFloat(index) * pageW
            }
            animating = false
            showToast("已加入待删 · 共 \(pending.count) 张")
            preheat(pageW: pageW)
        }
    }

    /// 下滑：标为系统相册里的「喜欢」，然后自动看下一张
    private func addToFavorites(pageW: CGFloat) {
        guard index < assets.count else { return }
        let asset = assets[index]

        animating = true
        haptic(style: .light)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            dragY = 0
        }

        Task { @MainActor in
            await library.setFavorite(asset, value: true)
            showToast("已加入「喜欢」")
            try? await Task.sleep(nanoseconds: 240_000_000)

            let target = min(index + 1, assets.count - 1)
            if target != index {
                index = target
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollX = CGFloat(target) * pageW
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                animating = false
                preheat(pageW: pageW)
            }
        }
    }

    // MARK: - 数据

    private func loadList() async {
        let all = await library.assets(for: category)
        let queued = Set(PendingStore.shared.ids)
        let filtered = all.filter { !queued.contains($0.localIdentifier) }

        await MainActor.run {
            assets = filtered
            index = 0
            scrollX = 0
            dragY = 0
            loading = false
        }
        preheat(pageW: max(UIScreen.main.bounds.width, 1))
    }

    private func preheat(pageW: CGFloat) {
        guard !assets.isEmpty else { return }
        let low = max(0, index - 1)
        let high = min(assets.count, index + 3)
        guard low < high else { return }

        let scale = UIScreen.main.scale
        let cardW = max(pageW - 26, 80)
        let cardH = max(UIScreen.main.bounds.height - 142, 80)
        library.preheat(Array(assets[low..<high]),
                        targetSize: CGSize(width: cardW * scale, height: cardH * scale))
    }

    private var toastLayer: some View {
        VStack {
            Spacer()
            if let toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                if toast == text { toast = nil }
            }
        }
    }

    private func haptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - 单张照片卡片

struct PhotoCard: View {
    let asset: PHAsset
    var onPlay: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.08))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 24, weight: .light))
                        Text("这张还在 iCloud 里")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.35))
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }

                if asset.mediaType == .video {
                    videoOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                if asset.mediaType == .video, let onPlay {
                    onPlay()
                }
            }
            .task(id: asset.localIdentifier) {
                let target = CGSize(width: max(geo.size.width, 1) * UIScreen.main.scale,
                                    height: max(geo.size.height, 1) * UIScreen.main.scale)
                for await loaded in PhotoLibrary.shared.imageStream(for: asset, targetSize: target) {
                    await MainActor.run {
                        image = loaded
                        failed = false
                    }
                }
                await MainActor.run {
                    if image == nil { failed = true }
                }
            }
        }
    }

    private var videoOverlay: some View {
        ZStack {
            Image(systemName: "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                }

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                        Text(durationText)
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.45), in: Capsule())

                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var durationText: String {
        let total = Int(asset.duration.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
