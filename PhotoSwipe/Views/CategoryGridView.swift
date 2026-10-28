import SwiftUI
import Photos
import UIKit

struct CategoryGridView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore

    var limited: Bool = false

    @State private var showTrash = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

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

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SmartCategory.allCases) { category in
                        NavigationLink {
                            SwipeViewerView(category: category)
                        } label: {
                            CategoryTile(
                                category: category,
                                count: library.counts[category] ?? 0,
                                cover: library.coverImage(for: category)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
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
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
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
