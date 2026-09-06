import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        FusionDashboard()
            // 真毛玻璃底：窗口透明 + NSVisualEffectView 采样“窗口背后”的内容。
            // 拖动 Fusion 窗口到不同页面/桌面时，底色与卡片玻璃会随背后内容变化。
            .background { FrostedBackdrop() }
            .background(WindowTransparencyAccessor())
            .frame(minWidth: 1040, minHeight: 700)
    }
}

/// 画布底色：整窗系统毛玻璃材质（会随背后内容变化）+ 一层极淡的深浅色自适应着色，
/// 只负责让空白区域有柔和质感、文字可读，不遮挡玻璃卡对背后内容的折射。
private struct FrostedBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectBackdrop()
            LinearGradient(
                colors: tintColors,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var tintColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.06, green: 0.09, blue: 0.20).opacity(0.30),
                Color(red: 0.05, green: 0.16, blue: 0.22).opacity(0.22),
                Color(red: 0.18, green: 0.10, blue: 0.24).opacity(0.26)
            ]
        }
        return [
            Color(red: 0.72, green: 0.86, blue: 1.0).opacity(0.16),
            Color(red: 0.66, green: 0.92, blue: 0.87).opacity(0.14),
            Color(red: 0.82, green: 0.74, blue: 1.0).opacity(0.16)
        ]
    }
}

/// NSVisualEffectView：以 .behindWindow 模式采样窗口背后的内容做模糊，
/// 这才是“拖到别的页面上颜色跟着变”的真毛玻璃（窗口需透明，见下方 Accessor）。
private struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 把宿主窗口设为透明：透明窗口 + behindWindow 材质才能看到并模糊窗口背后的桌面/其它窗口。
private struct WindowTransparencyAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentWindowHostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TransparentWindowHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}
