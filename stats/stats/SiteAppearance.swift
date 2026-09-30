import SwiftUI
import Combine

enum SiteAppearanceMode: String, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SitePalette: String, CaseIterable, Identifiable {
    case ocean, forest, sunset, violet
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SiteVisualStyle: String, CaseIterable, Identifiable {
    case classic, soft, sharp
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func radius(_ classic: CGFloat) -> CGFloat {
        switch self {
        case .classic: return classic
        case .soft: return classic + 10
        case .sharp: return 2
        }
    }
}

struct SiteAppearance {
    var mode: SiteAppearanceMode = .dark
    var palette: SitePalette = .ocean
    var style: SiteVisualStyle = .classic

    private var colors: (background: UInt32, panel: UInt32, accent: UInt32) {
        switch (palette, mode) {
        case (.ocean, .dark): return (0x0b0f14, 0x0f1620, 0x6ee7ff)
        case (.ocean, .light): return (0xf4f6f9, 0xffffff, 0x0284c7)
        case (.forest, .dark): return (0x0b1411, 0x111f19, 0x8be0b0)
        case (.forest, .light): return (0xf0f6f1, 0xfbfefb, 0x216d43)
        case (.sunset, .dark): return (0x19110e, 0x261b16, 0xffb784)
        case (.sunset, .light): return (0xfcf3eb, 0xfffdf9, 0xa44b16)
        case (.violet, .dark): return (0x12101c, 0x1d192a, 0xc6adff)
        case (.violet, .light): return (0xf5f1fc, 0xfefcff, 0x7543ae)
        }
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }

    var background: Color { color(colors.background) }
    var panel: Color { color(colors.panel) }
    var accent: Color { color(colors.accent) }
    var onAccent: Color { mode == .light ? .white : .black }
}

private struct SiteAppearanceKey: EnvironmentKey {
    static let defaultValue = SiteAppearance()
}

extension EnvironmentValues {
    var siteAppearance: SiteAppearance {
        get { self[SiteAppearanceKey.self] }
        set { self[SiteAppearanceKey.self] = newValue }
    }
}

final class SiteTheme: ObservableObject {
    static let shared = SiteTheme()
    private let defaults: UserDefaults

    @Published var mode: SiteAppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: "srTheme") }
    }
    @Published var palette: SitePalette {
        didSet { defaults.set(palette.rawValue, forKey: "srPalette") }
    }
    @Published var style: SiteVisualStyle {
        didSet { defaults.set(style.rawValue, forKey: "srStyle") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = SiteAppearanceMode(rawValue: defaults.string(forKey: "srTheme") ?? "") ?? .dark
        palette = SitePalette(rawValue: defaults.string(forKey: "srPalette") ?? "") ?? .ocean
        style = SiteVisualStyle(rawValue: defaults.string(forKey: "srStyle") ?? "") ?? .classic
    }

    var colorScheme: ColorScheme { mode == .light ? .light : .dark }
    var appearance: SiteAppearance { SiteAppearance(mode: mode, palette: palette, style: style) }
}

