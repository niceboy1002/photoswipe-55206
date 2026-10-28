import SwiftUI
import Photos
import UIKit

struct SwipeViewerView: View {
    let category: SmartCategory

    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var axis: DragAxis? = nil
    @State private var animating = false
    @State private var loading = true
    @State private var toast: String? = nil
    @State private var showTrash = false

    private enum DragAxis: Equatable { case horizontal, vertical }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                stage(geo)
                    .padding(.top, 60)
                    .padding(.bottom, 90)

                VStack {
                    topBar
                    Spacer()
                }

                VStack {
                    Spacer()
                    bottomBar
                }

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 120)
                    }
                    .transition(.opacity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await loadList() }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .onDisappear {
            library.stopPreheat()
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private func stage(_ geo: GeometryProxy) -> some View {
        if loading {
            ProgressView().tint(.white.opacity(0.5))
        } else if assets.isEmpty {
            emptyState
        } else {
            ZStack {
                if index + 1 < assets.count {
                    PhotoCard(asset: assets[index + 1])
                        .scaleEffect(0.93)
                        .opacity(0.45)
                        .allowsHitTesting(false)
                }

                PhotoCard(asset: assets[index])
                    .offset(x: drag.width, y: drag.height)
                    .rotationEffect(.degrees(Double(drag.width) / 26))
                    .gesture(dragGesture(geo))

                // 方向提示固定在屏幕中央，不跟着卡片跑
                verticalFeedback
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("这个分类处理完了")
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
        let total = library.counts[category] ?? assets.count
        return "\(index + 1) / \(total)"
    }

    // MARK: - 底部提示

    private var bottomBar: some View {
        HStack(spacing: 26) {
            hint(icon: "arrow.left.arrow.right", text: "切换")
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
    private var verticalFeedback: some View {
        if drag.height < -28 {
            feedbackBadge(symbol: "trash.fill",
                          text: "加入待删",
                          tint: .red,
                          progress: min(-drag.height / 130, 1))
        } else if drag.height > 28 {
            feedbackBadge(symbol: "heart.fill",
                          text: "加入喜欢",
                          tint: .pink,
                          progress: min(drag.height / 130, 1))
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
        .opacity(progress)
        .scaleEffect(0.72 + progress * 0.28)
    }

    // MARK: - 手势

    private func dragGesture(_ geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !animating else { return }

                if axis == nil {
                    let t = value.translation
                    if abs(t.width) > 9 || abs(t.height) > 9 {
                        axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                    }
                }

                switch axis {
                case .some(.horizontal):
                    drag = CGSize(width: value.translation.width,
                                  height: value.translation.height * 0.14)
                case .some(.vertical):
                    drag = CGSize(width: value.translation.width * 0.1,
                                  height: value.translation.height)
                case .none:
                    drag = CGSize(width: value.translation.width * 0.35,
                                  height: value.translation.height * 0.35)
                }
            }
            .onEnded { value in
                defer { axis = nil }
                guard !animating else { return }

                let thresholdX = geo.size.width * 0.24
                let thresholdY = geo.size.height * 0.11

                if axis == .some(.horizontal), abs(value.translation.width) > thresholdX {
                    step(value.translation.width < 0 ? 1 : -1)
                } else if axis == .some(.vertical), value.translation.height < -thresholdY {
                    markForDeletion()
                } else if axis == .some(.vertical), value.translation.height > thresholdY {
                    addToFavorites()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        drag = .zero
                    }
                }
            }
    }

    // MARK: - 三种动作

    /// 左右滑：上一张 / 下一张
    private func step(_ direction: Int) {
        guard !animating else { return }
        let target = index + direction
        guard target >= 0, target < assets.count else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { drag = .zero }
            showToast(direction > 0 ? "已经是最后一张了" : "已经是第一张了")
            return
        }

        animating = true
        withAnimation(.easeOut(duration: 0.2)) {
            drag = CGSize(width: direction > 0 ? -700 : 700, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            index = target
            drag = .zero
            animating = false
            preheat()
        }
    }

    /// 上滑：加入待删队列（不删除、不打断、不弹窗）
    private func markForDeletion() {
        guard !animating, index < assets.count else { return }
        animating = true

        let asset = assets[index]
        pending.add(asset.localIdentifier)

        withAnimation(.easeIn(duration: 0.26)) {
            drag = CGSize(width: drag.width, height: -900)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if index < assets.count {
                assets.remove(at: index)
            }
            if assets.isEmpty {
                index = 0
            } else if index >= assets.count {
                index = assets.count - 1
            }
            drag = .zero
            animating = false
            showToast("已加入待删 · 共 \(pending.count) 张")
        }
    }

    /// 下滑：直接标为系统相册里的「喜欢」，然后自动看下一张
    private func addToFavorites() {
        guard !animating, index < assets.count else { return }
        animating = true

        let asset = assets[index]

        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            drag = .zero
        }

        Task { @MainActor in
            await library.setFavorite(asset, value: true)
            showToast("已加入「喜欢」")
            try? await Task.sleep(nanoseconds: 260_000_000)
            animating = false
            if index + 1 < assets.count {
                step(1)
            }
        }
    }

    // MARK: - 数据

    private func loadList() async {
        let all = await library.assets(for: category)
        let filtered = all.filter { !PendingStore.shared.contains($0.localIdentifier) }
        await MainActor.run {
            assets = filtered
            index = 0
            loading = false
        }
        preheat()
    }

    private func preheat() {
        guard !assets.isEmpty else { return }
        let start = max(0, index)
        let end = min(assets.count, index + 3)
        guard start < end else { return }
        let scale = UIScreen.main.scale
        let size = CGSize(width: UIScreen.main.bounds.width * scale,
                          height: UIScreen.main.bounds.height * scale)
        library.preheat(Array(assets[start..<end]), targetSize: size)
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                if toast == text { toast = nil }
            }
        }
    }
}

// MARK: - 单张照片卡片

struct PhotoCard: View {
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.08))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.35))
                }

                // 视频角标
                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: asset.localIdentifier) {
                let target = CGSize(width: geo.size.width * UIScreen.main.scale,
                                    height: geo.size.height * UIScreen.main.scale)
                image = await PhotoLibrary.shared.image(for: asset, targetSize: target)
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
