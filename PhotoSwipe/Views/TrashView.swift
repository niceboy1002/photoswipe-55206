import SwiftUI
import Photos
import UIKit

struct TrashView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var loading = true
    @State private var deleting = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 4)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if loading {
                    ProgressView().tint(.white.opacity(0.5))
                } else if assets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        notice
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 12)

                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                TrashThumb(asset: asset) {
                                    remove(asset)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !assets.isEmpty {
                    deleteBar
                }
            }
            .navigationTitle("待删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task { await loadAssets() }
            .alert("删除失败", isPresented: $showError) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - 子视图

    private var notice: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 13))
                .foregroundStyle(.green)
            Text("删除后会进入系统「最近删除」，30 天内都能恢复")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("队列是空的")
                .font(.system(size: 15, weight: .semibold))
            Text("回到相册，向上滑动照片就会出现在这里")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var deleteBar: some View {
        VStack(spacing: 8) {
            Button {
                deleteAll()
            } label: {
                ZStack {
                    if deleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("全部删除 \(assets.count) 张")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(deleting)

            Text("系统会再确认一次，点「删除」即可")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - 数据

    private func loadAssets() async {
        let ids = pending.ids
        guard !ids.isEmpty else {
            await MainActor.run { loading = false }
            return
        }

        let ordered = await withCheckedContinuation { (cont: CheckedContinuation<[PHAsset], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var map: [String: PHAsset] = [:]
                fetched.enumerateObjects { asset, _, _ in
                    map[asset.localIdentifier] = asset
                }
                // 按入队顺序排列，而不是系统返回顺序
                cont.resume(returning: ids.compactMap { map[$0] })
            }
        }

        await MainActor.run {
            assets = ordered
            loading = false
        }
    }

    private func remove(_ asset: PHAsset) {
        pending.remove(asset.localIdentifier)
        withAnimation(.easeOut(duration: 0.2)) {
            assets.removeAll { $0.localIdentifier == asset.localIdentifier }
        }
    }

    private func deleteAll() {
        guard !deleting else { return }
        deleting = true
        let ids = pending.ids

        Task {
            do {
                try await library.delete(ids: ids)
                await MainActor.run {
                    pending.clear()
                    assets.removeAll()
                    deleting = false
                    dismiss()
                }
                await library.loadCounts()
                await library.loadCoverImages()
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    deleting = false
                    // 用户点了系统的「取消」，不算错误，安静返回
                    if !message.lowercased().contains("cancel") {
                        errorMessage = message
                        showError = true
                    }
                }
            }
        }
    }
}

// MARK: - 队列里的缩略图

struct TrashThumb: View {
    let asset: PHAsset
    let onRemove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    // 和分类格子一样的坑：不框死尺寸的话，宽幅照片会溢出去，
                    // 盖住隔壁格子的 × 按钮，让那个按钮点不动
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.black.opacity(0.65), in: Circle())
                }
                .padding(4)
            }
            .task(id: asset.localIdentifier) {
                image = await PhotoLibrary.shared.image(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300)
                )
            }
    }
}
