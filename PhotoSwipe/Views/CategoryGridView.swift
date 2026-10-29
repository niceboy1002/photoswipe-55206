import SwiftUI
import Photos
import UIKit

struct CategoryGridView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore

    var limited: Bool = false

    @State private var showTrash = false

    /// 缩放转场的身份空间：起点卡片和终点页面靠它配对
    @Namespace private var zoomNS

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private let smartColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if limited {
                    LimitedBanner {
                        library.presentLimitedPicker()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                NavigationLink {
                    SwipeViewerView(category: .all)
                        .zoomDestination(id: "hero-all", in: zoomNS)
                } label: {
                    AllPhotosHero(
                        count: library.counts[.all] ?? 0,
                        cover: library.coverImage(for: .all)
                    )
                    .zoomSource(id: "hero-all", in: zoomNS)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                sectionHeader("智能整理")

                LazyVGrid(columns: smartColumns, spacing: 8) {
                    NavigationLink {
                        SimilarGroupsView()
                    } label: {
                        SmartTile(icon: "photo.stack", title: "相似 / 连拍",
                                  subtitle: "自动成组，一次清一组", tint: Color(hex: "#8B7BE8") ?? .purple)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MonthListView()
                    } label: {
                        SmartTile(icon: "calendar", title: "按月整理",
                                  subtitle: "一个月一个月过", tint: Color(hex: "#4FB8C4") ?? .teal)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        OldScreenshotsView()
                    } label: {
                        SmartTile(icon: "clock.arrow.circlepath", title: "过期截屏",
                                  subtitle: "90 天前的", tint: Color(hex: "#D89A5A") ?? .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BlurryPhotosView()
                    } label: {
                        SmartTile(icon: "camera.filters", title: "可能拍糊",
                                  subtitle: "自动挑虚焦的", tint: Color(hex: "#D97C99") ?? .pink)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                sectionHeader("分类")

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SmartCategory.gridCases) { category in
                        NavigationLink {
                            SwipeViewerView(category: category)
                                .zoomDestination(id: category.rawValue, in: zoomNS)
                        } label: {
                            CategoryTile(
                                category: category,
                                count: library.counts[category] ?? 0,
                                cover: library.coverImage(for: category)
                            )
                            // 点哪一格，哪一格就长大成整页
                            .zoomSource(id: category.rawValue, in: zoomNS)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(Color.black)
            .scrollIndicators(.hidden)
            .navigationTitle("图库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTrash = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.white)
                                .padding(.trailing, 2)

                            if pending.count > 0 {
                                Text("\(pending.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 9, y: -7)
                            }
                        }
                    }
                    .disabled(pending.isEmpty)
                    .opacity(pending.isEmpty ? 0.35 : 1)
                }
            }
            .sheet(isPresented: $showTrash) {
                TrashView()
            }
            .task {
                if library.status == .authorized || library.status == .limited {
                    if library.counts.isEmpty {
                        await library.loadCounts()
                    }
                    await library.loadCoverImages()
                }
            }
        }
    }
}

// MARK: - 「全部照片」入口

struct AllPhotosHero: View {
    let count: Int
    let cover: UIImage?

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#3B3B4A") ?? .gray, Color(hex: "#15151C") ?? .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                    .clipped()
                    .blur(radius: 1)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("全部照片")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("共 \(count) 项 · 从头滑一遍")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
        .opacity(count == 0 ? 0.45 : 1)
    }
}

// MARK: - 分类卡片

struct CategoryTile: View {
    let category: SmartCategory
    let count: Int
    let cover: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tileGradient)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let cover {
                    // 这一步是修「点偏」的关键：
                    // 全景封面的长宽比极端（可能 3:1 甚至更宽），scaledToFill 会横向溢出好几倍。
                    // 视觉上被外层的 clipShape 裁掉了，但**点击区域不会被裁**，
                    // 于是它溢出的那部分会盖住左边的「视频」格子，把点击抢走。
                    // 所以在图片自己身上先框死尺寸再 clipped()，再补一层 contentShape，
                    // 让图片自身和整格的可点范围都严格等于这一格。
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                }
            }
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 3)
                    Text(category.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.leading, 9)
                .padding(.bottom, 9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            // 可点区域严格等于这一格自己，隔壁不会再抢
            .contentShape(Rectangle())
            .opacity(count == 0 ? 0.42 : 1)
    }

    private var tileGradient: LinearGradient {
        let colors = category.colors.compactMap { Color(hex: $0) }
        return LinearGradient(
            colors: colors.isEmpty ? [Color.gray, Color.black] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 受限访问提示

struct LimitedBanner: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            Text("你只允许访问部分照片")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button("去设置", action: action)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 十六进制颜色

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
