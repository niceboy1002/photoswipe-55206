import Foundation
import Photos
import UIKit
import CoreGraphics

/// 一张照片的「指纹」。
/// hash 是感知哈希（dHash），blur 是拉普拉斯方差（越小越糊）。
/// 两个值都从**同一次**缩略图请求里算出来，所以做相似分组时
/// 拍糊检测是顺带完成的，不额外花时间。
struct PhotoFingerprint {
    let id: String
    let hash: UInt64
    let blur: Float
    let date: Double
}

/// 本地图像分析器。
///
/// 只做两件事：
/// 1. 给每张照片算一个 64 位感知哈希，用来找「长得像」的照片
/// 2. 算一个锐度分数，用来找「明显虚焦」的照片
///
/// 所有计算都在本机完成。缩略图请求显式关掉了 iCloud 下载
/// （`isNetworkAccessAllowed = false`），否则分析几万张照片会偷偷跑掉几个 G 流量。
///
/// 结果按 localIdentifier 缓存在 Caches 目录，第二次打开是瞬时的。
final class ImageAnalyzer: ObservableObject {
    static let shared = ImageAnalyzer()

    /// 「明显虚焦」的判定线。
    /// 64×64 灰度图上做 4 邻域拉普拉斯，取方差：
    /// 正常照片通常在几百以上，明显失焦会掉到个位数。
    /// 取 20 是偏保守的值——宁可漏掉几张，也不要把正常照片标成糊的。
    static let blurThreshold: Float = 20

    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var doneCount = 0
    @Published private(set) var totalCount = 0
    /// 只在 iCloud 上、本机没有副本，因此跳过的张数
    @Published private(set) var cloudSkipped = 0
    @Published private(set) var cachedCount = 0

    private var prints: [String: PhotoFingerprint] = [:]
    private var loaded = false
    private var stopRequested = false

    /// 落盘用的紧凑结构。哈希存成十六进制字符串，
    /// 避免 JSON 数字精度在 UInt64 上出问题。
    private struct StoredPrint: Codable {
        let i: String
        let h: String
        let b: Float
        let d: Double
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("photoswipe-fingerprints.json")
    }

    // MARK: - 缓存读写

    @MainActor
    func loadCacheIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let list = try? JSONDecoder().decode([StoredPrint].self, from: data) else {
            cachedCount = 0
            return
        }
        var map: [String: PhotoFingerprint] = [:]
        map.reserveCapacity(list.count)
        for item in list {
            guard let h = UInt64(item.h, radix: 16) else { continue }
            map[item.i] = PhotoFingerprint(id: item.i, hash: h, blur: item.b, date: item.d)
        }
        prints = map
        cachedCount = map.count
    }

    private func saveCache() {
        let list = prints.values.map {
            StoredPrint(i: $0.id, h: String($0.hash, radix: 16), b: $0.blur, d: $0.date)
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        // 写盘放后台：几千条序列化后有好几百 KB，
        // 在分析循环里同步写会一笔一笔卡住主线程
        let url = cacheURL
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: url, options: .atomic)
        }
    }

    @MainActor
    func clearCache() {
        prints.removeAll()
        cachedCount = 0
        loaded = true
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func stop() {
        stopRequested = true
    }

    // MARK: - 分析

    /// 遍历给定照片。已经算过的会跳过，所以中断后再进来是接着做的。
    /// 需要分析的就补上，已经算完的直接返回。
    ///
    /// 上次分析到一半退出、或者又拍了新照片，都靠这里续上。
    /// 待补的张数很少时静默跑完——否则会闪一下全屏进度条，看着像出了问题。
    @MainActor
    func ensureAnalyzed(_ photos: [PHAsset], limit: Int = 5000) async {
        loadCacheIfNeeded()
        let targets = photos.count > limit ? Array(photos.prefix(limit)) : photos
        let todo = targets.reduce(0) { $0 + (prints[$1.localIdentifier] == nil ? 1 : 0) }
        guard todo > 0 else { return }
        await analyze(photos, limit: limit, silent: todo <= 60)
    }

    @MainActor
    func analyze(_ photos: [PHAsset], limit: Int = 5000, silent: Bool = false) async {
        guard !running else { return }
        loadCacheIfNeeded()
        guard !photos.isEmpty else { return }

        let targets = photos.count > limit ? Array(photos.prefix(limit)) : photos

        running = !silent
        stopRequested = false
        totalCount = targets.count
        doneCount = 0
        progress = 0
        cloudSkipped = 0

        var fresh = 0
        for (i, asset) in targets.enumerated() {
            if stopRequested { break }

            if prints[asset.localIdentifier] == nil {
                if let fp = await Self.fingerprint(of: asset) {
                    prints[fp.id] = fp
                    fresh += 1
                    // 每 400 张落一次盘：中途被杀掉也不会全部白算
                    if fresh % 400 == 0 { saveCache() }
                } else {
                    cloudSkipped += 1
                }
            }

            doneCount = i + 1
            progress = Double(i + 1) / Double(max(targets.count, 1))
            // 每 20 张让一次主线程，滚动和动画不会被分析卡住
            if i % 20 == 0 { await Task.yield() }
        }

        saveCache()
        cachedCount = prints.count
        running = false
        if !silent { progress = 1 }
    }

    // MARK: - 查询

    func blurScore(for id: String) -> Float? {
        prints[id]?.blur
    }

    func isLikelyBlurry(_ id: String) -> Bool {
        guard let fp = prints[id] else { return false }
        return fp.blur > 0 && fp.blur < Self.blurThreshold
    }

    /// 相似 / 连拍分组。连拍排在前面。
    ///
    /// 连拍不需要哈希——`burstIdentifier` 是系统给的原生标记，最准也最快，
    /// 所以即使照片还在 iCloud 上没分析过，连拍组也能正常出来。
    @MainActor
    func similarityGroups(from all: [PHAsset], limit: Int = 300) -> [PhotoGroup] {
        loadCacheIfNeeded()

        var groups: [PhotoGroup] = []
        var usedByBurst = Set<String>()

        // 1) 连拍
        var bursts: [String: [PHAsset]] = [:]
        for asset in all {
            guard asset.mediaType == .image, let bid = asset.burstIdentifier else { continue }
            bursts[bid, default: []].append(asset)
        }

        var burstGroups: [PhotoGroup] = []
        for (bid, list) in bursts where list.count >= 2 {
            let sorted = list.sorted {
                ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }
            for asset in sorted { usedByBurst.insert(asset.localIdentifier) }
            burstGroups.append(
                PhotoGroup(
                    id: "burst:\(bid)",
                    kind: .burst,
                    title: "连拍 · \(sorted.count) 张",
                    subtitle: Self.dateText(sorted.last?.creationDate),
                    assets: sorted
                )
            )
        }
        burstGroups.sort { lhs, rhs in
            (lhs.assets.last?.creationDate ?? .distantPast) > (rhs.assets.last?.creationDate ?? .distantPast)
        }
        groups.append(contentsOf: burstGroups)

        // 2) 视觉相似
        groups.append(contentsOf: Self.similarGroups(prints: prints,
                                                     all: all,
                                                     skip: usedByBurst,
                                                     limit: max(limit - burstGroups.count, 0)))

        return Array(groups.prefix(limit))
    }

    /// 拍糊候选，按「糊的程度」从重到轻排
    @MainActor
    func blurryAssets(from all: [PHAsset]) -> [PHAsset] {
        loadCacheIfNeeded()
        var scored: [(asset: PHAsset, blur: Float)] = []
        for asset in all {
            guard asset.mediaType == .image else { continue }
            guard let fp = prints[asset.localIdentifier] else { continue }
            guard fp.blur > 0, fp.blur < Self.blurThreshold else { continue }
            scored.append((asset, fp.blur))
        }
        scored.sort { $0.blur < $1.blur }
        return scored.map { $0.asset }
    }

    // MARK: - 分组算法

    private static func similarGroups(prints: [String: PhotoFingerprint],
                                      all: [PHAsset],
                                      skip: Set<String>,
                                      limit: Int) -> [PhotoGroup] {
        guard limit > 0 else { return [] }

        // 候选池：有指纹、不是视频、没被连拍组拿走
        var pool: [(id: String, hash: UInt64, date: Double)] = []
        pool.reserveCapacity(prints.count)
        for asset in all {
            let id = asset.localIdentifier
            guard asset.mediaType == .image, !skip.contains(id) else { continue }
            guard let fp = prints[id] else { continue }
            pool.append((id, fp.hash, fp.date))
        }
        guard pool.count >= 2 else { return [] }

        // 并查集
        var parent = Array(0..<pool.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        // 分桶加速：64 位哈希切成 4 段 16 位，
        // 只有某一段完全相同的两张才会被拿来比距离。
        // 全量两两比较在 5000 张上是 1250 万次，分桶后只剩几万次。
        let bandCount = 4
        let bandMask: UInt64 = 0xFFFF
        var buckets = [[UInt64: [Int]]](repeating: [:], count: bandCount)

        for (i, item) in pool.enumerated() {
            for b in 0..<bandCount {
                let shift = UInt64(64 - 16 * (b + 1))
                let key = (item.hash >> shift) & bandMask
                buckets[b][key, default: []].append(i)
            }
        }

        let maxDistance = 10          // 64 位里最多差 10 位，算「长得像」
        let maxGap: Double = 30 * 86400

        for b in 0..<bandCount {
            for (_, list) in buckets[b] {
                // 一个桶里塞了几十张，说明这组哈希太常见（比如大片纯色），
                // 比下去只会把不相干的照片粘成一大坨，直接跳过
                guard list.count >= 2, list.count <= 40 else { continue }

                for i in 0..<(list.count - 1) {
                    for j in (i + 1)..<list.count {
                        let a = pool[list[i]]
                        let c = pool[list[j]]
                        let distance = hamming(a.hash, c.hash)
                        // 极近的（几乎同一张）不限制时间；
                        // 只是有点像的，要求拍摄时间在 30 天内，
                        // 否则 2019 年的日落会和 2024 年的日落凑成一组
                        if distance <= 4 || (distance <= maxDistance && abs(a.date - c.date) <= maxGap) {
                            union(list[i], list[j])
                        }
                    }
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<pool.count {
            members[find(i), default: []].append(i)
        }

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.localIdentifier, $0) })
        var result: [PhotoGroup] = []

        for (_, idxList) in members where idxList.count >= 2 {
            var assets: [PHAsset] = []
            for i in idxList {
                if let asset = byID[pool[i].id] { assets.append(asset) }
            }
            guard assets.count >= 2 else { continue }
            assets.sort {
                ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }
            result.append(
                PhotoGroup(
                    id: "sim:\(assets[0].localIdentifier)",
                    kind: .similar,
                    title: "相似 · \(assets.count) 张",
                    subtitle: Self.dateText(assets.last?.creationDate),
                    assets: assets
                )
            )
        }

        result.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.assets.last?.creationDate ?? .distantPast) > (rhs.assets.last?.creationDate ?? .distantPast)
        }
        return Array(result.prefix(limit))
    }

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        var v = a ^ b
        var count = 0
        while v != 0 {
            v &= (v - 1)
            count += 1
        }
        return count
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 指纹计算

extension ImageAnalyzer {
    static func fingerprint(of asset: PHAsset) async -> PhotoFingerprint? {
        guard asset.mediaType == .image else { return nil }
        guard let thumb = await thumbnail(of: asset), let cg = thumb.cgImage else { return nil }

        // 像素运算放到后台队列，主线程只负责等结果
        let values: (UInt64, Float)? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: analyse(cg))
            }
        }
        guard let values else { return nil }

        return PhotoFingerprint(
            id: asset.localIdentifier,
            hash: values.0,
            blur: values.1,
            date: (asset.creationDate ?? .distantPast).timeIntervalSince1970
        )
    }

    private static func thumbnail(of asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false   // 不为了分析去下载 iCloud 原图
            options.version = .current

            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 128, height: 128),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if resumed { return }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

                if let image {
                    resumed = true
                    continuation.resume(returning: image)
                } else if !degraded || cancelled {
                    // 没有图，也没有后续回调了，直接放弃这张
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 把图缩到 64×64 灰度，一次遍历同时算 dHash 和锐度
    private static func analyse(_ image: CGImage) -> (UInt64, Float)? {
        let side = 64
        var buffer = [UInt8](repeating: 0, count: side * side)
        var result: (UInt64, Float)?

        // 注意：必须让 CGContext 和绘制都在 withUnsafeMutableBytes 里完成。
        // 如果只把 &buffer 交给 CGContext、出了闭包再绘制，
        // 那块内存已经失效了，画进去的是野指针。
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

            let pixels = base.assumingMemoryBound(to: UInt8.self)
            result = (dHash(pixels, side: side), laplacianVariance(pixels, side: side))
        }

        return result
    }

    /// 差异哈希：把图压成 9×8 的灰度网格，比较左右相邻两格的大小关系，得到 64 位。
    /// 它对亮度、对比度、整体缩放都不敏感，只关心「结构」。
    private static func dHash(_ pixels: UnsafeMutablePointer<UInt8>, side: Int) -> UInt64 {
        var grid = [[Int]](repeating: [Int](repeating: 0, count: 9), count: 8)

        for row in 0..<8 {
            let y0 = row * side / 8
            let y1 = max((row + 1) * side / 8, y0 + 1)
            for col in 0..<9 {
                let x0 = col * side / 9
                let x1 = max((col + 1) * side / 9, x0 + 1)
                var sum = 0
                var n = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        sum += Int(pixels[y * side + x])
                        n += 1
                    }
                }
                grid[row][col] = n > 0 ? sum / n : 0
            }
        }

        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<8 {
            for col in 0..<8 {
                if grid[row][col] > grid[row][col + 1] {
                    hash |= (UInt64(1) << UInt64(bit))
                }
                bit += 1
            }
        }
        return hash
    }

    /// 拉普拉斯方差。边缘处灰度二阶导越大，方差越高，图越锐。
    /// 全图失焦时灰度变化平缓，方差会明显塌下来。
    private static func laplacianVariance(_ pixels: UnsafeMutablePointer<UInt8>, side: Int) -> Float {
        var sum = 0.0
        var sumSquares = 0.0
        var n = 0.0

        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let center = Double(pixels[y * side + x])
                let value = 4 * center
                    - Double(pixels[y * side + x - 1])
                    - Double(pixels[y * side + x + 1])
                    - Double(pixels[(y - 1) * side + x])
                    - Double(pixels[(y + 1) * side + x])
                sum += value
                sumSquares += value * value
                n += 1
            }
        }

        guard n > 0 else { return 0 }
        let mean = sum / n
        return Float(max(sumSquares / n - mean * mean, 0))
    }
}
