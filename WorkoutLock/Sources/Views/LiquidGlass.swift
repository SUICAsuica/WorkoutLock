import SwiftUI

/// Liquid Glass 面の上で読みやすい、濃いブラウン系のテキスト色。
enum WorkoutInk {
    static let primary = Color(red: 0.23, green: 0.11, blue: 0.02)
}

/// iOS 26 の Liquid Glass を使う薄いラッパー。
/// iOS 26 以上では system の `glassEffect` を、未満では `.ultraThinMaterial` で近似する。
extension View {
    /// すりガラス面。カード・パネル・チップに使う。
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: shape)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.45), lineWidth: 1))
        }
    }
}

/// Liquid Glass の主ボタン（黒地・前面）。iOS 26 では glass prominent、未満は塗りで近似。
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return configuration.label
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.88), in: shape)
            .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPrimaryButtonStyle {
    static var glassPrimary: GlassPrimaryButtonStyle { GlassPrimaryButtonStyle() }
}
