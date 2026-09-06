import SwiftUI

/// 看板模块「活排版」公共约定与工具。
///
/// 所有模块（含以后新增的）的内容都必须用这套弹性排版，禁止「整卡等比缩放」的死板方式：
/// 1. 模块内容根视图用 GeometryReader 读取卡片实际尺寸；
/// 2. 用 textFactor(for:design:) 计算字号因子 f：只把文字整体放大/缩小，字形永不被压扁或拉长；
/// 3. 所有字号用 .system(size: 数值 * f) 表示；
/// 4. 段与段之间用 Spacer(minLength: 间隙 * f) 做弹性空隙：卡片变大时空隙均匀变宽、
///    内容纵向撑满整张卡，空白均匀分布在段落之间而不是堆在卡底；
/// 5. 关键数值可加 .lineLimit(1) / .minimumScaleFactor，行内放不下时只做等比缩字而非截断变形。
enum LiveLayout {
    /// 等比字号因子：卡片尺寸相对设计尺寸取较小方向的比例，限制在 0.45…2.0 之间。
    static func textFactor(for size: CGSize, design: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0, design.width > 0, design.height > 0 else { return 1 }
        return min(2.0, max(0.45, min(size.width / design.width, size.height / design.height)))
    }

    /// 把默认布局里的格子数换算成像素设计基准（画布：格宽 96、行高 108、间距 4）。
    /// 某模块的默认卡是多少格，就把该格数换算出的像素当设计尺寸，保证默认状态下 f ≈ 1。
    static func pixelDesign(columns: Int, rows: Int) -> CGSize {
        CGSize(
            width: CGFloat(columns) * DashboardCanvasLimits.cellWidth + CGFloat(max(0, columns - 1)) * 4,
            height: CGFloat(rows) * DashboardCanvasLimits.rowHeight + CGFloat(max(0, rows - 1)) * 4
        )
    }

    /// 占用颜色渐变：占用越低越绿、越高越红（色相从 120° 连续过渡到 0°，中间经过黄）；
    /// 数值不可用时用次要灰色。Mac 状态卡与 Codex 用量条共用同一套着色。
    static func usageColor(_ usage: Double?) -> Color {
        guard let usage else { return .secondary }
        let t = min(1, max(0, usage))
        return Color(hue: (1 - t) / 3, saturation: 0.9, brightness: 0.9)
    }

    /// 自绘占用进度条（Mac 状态卡等“占用条”用）：条宽与颜色都按占用比例，
    /// 占用越低越绿、越高越红。
    static func usageBar(progress: Double, factor f: CGFloat) -> some View {
        usageBar(progress: progress, colorUsage: progress, factor: f)
    }

    /// 自绘进度条，条宽与颜色分开控制：条宽 = progress（0…1），
    /// 颜色按 colorUsage 渐变（越低越绿、越高越红）。
    /// Codex 用量条用它：条宽表示“剩余比例”，颜色表示“已用方向”——
    /// 剩余越少（已用越高）条越短且越红，剩余充足时条长且绿。
    static func usageBar(progress: Double, colorUsage: Double?, factor f: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(usageColor(colorUsage ?? progress))
                    .frame(width: geo.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: max(3, 5 * f))
    }
}
