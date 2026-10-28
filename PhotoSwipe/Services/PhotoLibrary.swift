import Foundation
import Photos
import UIKit
import AVFoundation

/// PhotoKit 的唯一入口。
/// 所有重活（遍历、取图、删除）都丢到后台队列，主线程只负责刷新 UI。
final class PhotoLibrary: ObservableObject {
    static let shared = PhotoLibrary()

    @Published var status: PHAuthorizationStatus
    @Published var counts: [SmartCategory: Int] = [:]
    @Published var covers: [SmartCategory: String] = [:]   // 每个分类第一张的 localIdentifier，用来当封面
    @Published var isLoadingCounts = false
    @Published var lastError: String?

    /// 缓存每个分类的完整列表，避免每次进详情页都重新遍历
    private var listCache: [SmartCategory: [PHAsset]] = [:]
    /// 封面缩略图。加了 @Published，加载完成后网格会自动刷新
    @Published private var coverImageCache: [String: UIImage] = [:]

    /// 解码后的图片缓存。滑动时同一张图会被反复创建/销毁视图，
    /// 有这层缓存就不会每次都闪一下转圈。
    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    let imageManager = PHCachingImageManager()

    private init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - 权限

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 请求相册读写权限（删除照片需要 readWrite，不能用 addOnly）
    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { self.status = result }
        return result
    }

    /// 用户只授权了「部分照片」时，跳到系统设置重新选择。
    /// 注：presentLimitedLibraryPicker(from:) 在 iOS 18 的 SDK 里已不可用，
    /// 所以这里直接打开本 App 的设置页，用户在里面就能改照片权限。
    func presentLimitedPicker() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 统计与列表

    /// 统计每个分类的数量 + 取封面。全部在后台线程完成。
    func loadCounts() async {
        await MainActor.run { self.isLoadingCounts = true }

        let result = await withCheckedContinuation {
            (cont: CheckedContinuation<([SmartCategory: Int], [SmartCategory: String]), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var countMap: [SmartCategory: Int] = [:]
                var coverMap: [SmartCategory: String] = [:]
                for category in SmartCategory.allCases {
                    let fetched = category.fetchAssets()
                    countMap[category] = fetched.count
                    if fetched.count > 0 {
                        coverMap[category] = fetched.object(at: 0).localIdentifier
                    }
                }
                cont.resume(returning: (countMap, coverMap))
            }
        }

        await MainActor.run {
            self.counts = result.0
            self.covers = result.1
            self.isLoadingCounts = false
        }
    }

    /// 取出某个分类的全部资源。第一次会遍历，之后走缓存。
    func assets(for category: SmartCategory, forceRefresh: Bool = false) async -> [PHAsset] {
        if !forceRefresh, let cached = listCache[category] {
            return cached
        }
        let list = await withCheckedContinuation { (cont: CheckedContinuation<[PHAsset], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fetched = category.fetchAssets()
                var array: [PHAsset] = []
                array.reserveCapacity(fetched.count)
                fetched.enumerateObjects { asset, _, _ in array.append(asset) }
                cont.resume(returning: array)
            }
        }
        listCache[category] = list
        return list
    }

    func invalidateCache() {
        listCache.removeAll()
    }

    // MARK: - 取图

    private func cacheKey(_ asset: PHAsset, _ size: CGSize) -> NSString {
        "\(asset.localIdentifier)#\(Int(size.width.rounded()))x\(Int(size.height.rounded()))" as NSString
    }

    func cachedImage(for asset: PHAsset, targetSize: CGSize) -> UIImage? {
        imageCache.object(forKey: cacheKey(asset, targetSize))
    }

    /// 加载单张图片（一次性返回，适合缩略图）。
    func image(for asset: PHAsset, targetSize: CGSize?) async -> UIImage? {
        let size = targetSize ?? CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        let key = cacheKey(asset, size)
        if let hit = imageCache.object(forKey: key) { return hit }

        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true   // 关键：iCloud 里的照片也能取到
            options.version = .current

            var resumed = false
            self.imageManager.requestImage(for: asset,
                                           targetSize: size,
                                           contentMode: .aspectFill,
                                           options: options) { image, info in
                if let info = info, (info[PHImageCancelledKey] as? Bool) == true { return }
                guard !resumed else { return }
                resumed = true
                if let image {
                    self.imageCache.setObject(image, forKey: key, cost: self.cost(of: image))
                }
                cont.resume(returning: image)
            }
        }
    }

    /// 渐进式加载：先给一张模糊的（立刻显示），再给一张清晰的。
    /// 全屏浏览用它，滑起来才不会有"空白转圈"的瞬间。
    func imageStream(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<UIImage> {
        let key = cacheKey(asset, targetSize)

        if let hit = imageCache.object(forKey: key) {
            return AsyncStream { continuation in
                continuation.yield(hit)
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.version = .current

            var requestID: PHImageRequestID = 0
            requestID = self.imageManager.requestImage(for: asset,
                                                      targetSize: targetSize,
                                                      contentMode: .aspectFill,
                                                      options: options) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let failed = info?[PHImageErrorKey] != nil

                if let image {
                    // 模糊版不进缓存，否则下次打开还是糊的
                    if !degraded {
                        self.imageCache.setObject(image, forKey: key, cost: self.cost(of: image))
                    }
                    continuation.yield(image)
                }

                if cancelled || failed || !degraded {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                if requestID != 0 {
                    self.imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }

    private func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    /// 预取。滑动到第 N 张时，把前后几张提前读进缓存，滑起来才不会卡。
    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets,
                                        targetSize: targetSize,
                                        contentMode: .aspectFill,
                                        options: nil)
    }

    func stopPreheat() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - 视频

    /// 取可播放的 AVPlayerItem。
    /// 先走 requestPlayerItem（最省事）；iCloud 视频这条路径常常拿不到，
    /// 再退一步用 requestAVAsset 自己拼 AVPlayerItem。
    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        let readyItem: AVPlayerItem? = await withCheckedContinuation {
            (cont: CheckedContinuation<AVPlayerItem?, Never>) in
            self.imageManager.requestPlayerItem(forVideo: asset, options: options) { result, _ in
                cont.resume(returning: result)
            }
        }
        if let readyItem { return readyItem }

        let avAsset: AVAsset? = await withCheckedContinuation {
            (cont: CheckedContinuation<AVAsset?, Never>) in
            self.imageManager.requestAVAsset(forVideo: asset, options: options) { result, _, _ in
                cont.resume(returning: result)
            }
        }
        guard let avAsset else { return nil }
        return AVPlayerItem(asset: avAsset)
    }

    /// 播放前把音频会话切到 playback，否则手机开了静音开关就没有声音
    func activatePlaybackAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    // MARK: - 封面

    func coverImage(for category: SmartCategory) -> UIImage? {
        guard let id = covers[category] else { return nil }
        return coverImageCache[id]
    }

    func loadCoverImages() async {
        for category in SmartCategory.allCases {
            guard let id = covers[category],
                  coverImageCache[id] == nil else { continue }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = result.firstObject else { continue }
            if let thumb = await self.image(for: asset, targetSize: CGSize(width: 400, height: 400)) {
                await MainActor.run { self.coverImageCache[id] = thumb }
            }
        }
    }

    // MARK: - 删除

    /// 批量删除。PhotoKit 会把它们一次性移进「最近删除」，系统只弹一次确认。
    /// 删除后 30 天内都能在系统相册的「最近删除」里恢复，所以不需要我们自己做备份。
    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var targets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in targets.append(asset) }
        guard !targets.isEmpty else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(targets as NSArray)
        }

        await MainActor.run {
            self.listCache.removeAll()
            self.imageCache.removeAllObjects()
            for id in ids { self.coverImageCache.removeValue(forKey: id) }
        }
    }

    // MARK: - 收藏

    func setFavorite(_ asset: PHAsset, value: Bool) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = value
            }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }
}
