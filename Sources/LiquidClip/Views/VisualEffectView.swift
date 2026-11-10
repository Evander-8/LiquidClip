import SwiftUI
import AppKit

public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        visualEffectView.isEmphasized = isEmphasized
        return visualEffectView
    }
    
    public func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        visualEffectView.isEmphasized = isEmphasized
    }
}

// Liquid Glass View Modifier for high-end macOS frosted glass
public struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderOpacity: Double
    
    public init(cornerRadius: CGFloat = 16, borderOpacity: Double = 0.22) {
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(borderOpacity * 1.6), location: 0),
                                .init(color: Color.white.opacity(borderOpacity * 0.4), location: 0.4),
                                .init(color: Color.black.opacity(borderOpacity * 0.5), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, borderOpacity: Double = 0.22) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
    }
}
