import SwiftUI

/// The design system for Murmur.
///
/// Clean, minimalist, modern UI design tokens.
/// Every value a view needs lives here; components never declare their own colors, sizes,
/// radii or durations.
enum DS {

    // MARK: - Color

    enum Color {
        /// Main application background — crisp, modern, light.
        static let background = swatch(0xF8F9FA)
        /// Header bar background.
        static let header = swatch(0xFFFFFF)
        /// Card & row background.
        static let card = swatch(0xFFFFFF)
        /// Card hover state.
        static let cardHover = swatch(0xF3F4F6)
        /// Subtle card border.
        static let cardBorder = swatch(0xE5E7EB)
        /// Header and divider border.
        static let border = swatch(0xE5E7EB)
        /// Inner pill / tab background.
        static let tabBg = swatch(0xF1F3F5)
        static let tabActive = swatch(0xFFFFFF)
        static let tabBorder = swatch(0xE2E8F0)

        /// Legacy compatibility aliases
        static let chassis = background
        static let panel = card
        static let well = background
        static let deck = card
        static let cap = tabActive
        static let seam = border
        static let panelHighlight = cardBorder
        static let panelShade = background

        // Text — high contrast and crystal clear
        static let ink = swatch(0x111827)
        static let inkSecondary = swatch(0x4B5563)
        static let inkMuted = swatch(0x6B7280)
        static let silkscreen = inkSecondary
        static let inkOnDeck = ink

        // Accents
        static let accent = swatch(0x4F46E5) // Indigo
        static let accentSubtle = SwiftUI.Color(hex: 0x4F46E5).opacity(0.08)
        static let record = swatch(0xDC2626) // Red
        static let recordIdle = swatch(0xFEE2E2)
        static let success = swatch(0x059669) // Emerald
        static let info = swatch(0x0284C7) // Sky Blue
        static let meterFace = swatch(0xD8CFB4)
        static let meterLamp = swatch(0xE8B860)
        static let meterNeedle = swatch(0x1C1A17)
        static let meterGreen = success
        static let meterAmber = swatch(0xD97706)
        static let meterRed = record

        // Selection / Hover
        static let selection = swatch(0xF3F4F6)
        static let selectionEdge = swatch(0x4F46E5)
        static let focusRing = swatch(0x4F46E5)
        static let hover = cardHover

        // MARK: Helpers
        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }
    }

    // MARK: - Material

    /// The physical detail that makes a panel read as a machined object rather than a filled
    /// rectangle: metal grain, fasteners, ventilation, lamps, segmented readouts.
    ///
    /// These are what "lean into it" means here — density of real hardware detail, not
    /// decoration laid on top. Every one of them exists on a TC-D5 or a PMD.
    enum Material {
        // Brushed aluminum grain. Anisotropic: fine horizontal striations across the panel.
        /// Opacity of the lighter striations.
        static let grainLight: Double = 0.055
        /// Opacity of the darker striations.
        static let grainDark: Double = 0.07
        /// Distance between striations.
        static let grainPitch: CGFloat = 2
        /// Grain runs horizontally across a face, as on a rolled sheet.
        static let grainAngle: Angle = .degrees(0)

        // Fasteners
        /// Diameter of a panel screw head.
        static let screwSize: CGFloat = 9
        /// Inset of a screw from the panel corner.
        static let screwInset: CGFloat = 10

        // Ventilation
        /// A single vent slot.
        static let ventSlotWidth: CGFloat = 3
        static let ventSlotHeight: CGFloat = 22
        static let ventSlotGap: CGFloat = 4
        static let ventRadius: CGFloat = 1.5

        // Indicator lamps — small, hard-edged, lit from behind a lens.
        static let lampSize: CGFloat = 7
        /// A lit lamp's lens highlight — a specular dot, not a bloom.
        static let lampSpecular: Double = 0.45
        /// How far an unlit lamp sits below the lit value.
        static let lampUnlitOpacity: Double = 0.22

        // Segmented readout — the tape counter and timings.
        /// Stroke width of a seven-segment bar.
        static let segmentThickness: CGFloat = 3
        /// Gap between segments within a digit.
        static let segmentGap: CGFloat = 1
        /// Unlit segments stay faintly visible, as on a real LCD.
        static let segmentGhostOpacity: Double = 0.12

        // Transport keys — rectangular, wide, with real travel.
        static let keyHeight: CGFloat = 34
        static let keyMinWidth: CGFloat = 52
        /// How far a key sinks when pressed.
        static let keyTravel: CGFloat = 1.5

        // VU meter
        /// Total sweep of the needle, centered on vertical.
        static let needleSweep: Angle = .degrees(96)
        static let needleWidth: CGFloat = 1.5
        /// Where 0 VU sits along the scale, 0...1 — the red zone begins here.
        static let meterZeroPoint: Double = 0.72
    }

    // MARK: - Type

    /// A neutral grotesque, the way equipment was labeled. Helvetica Neue is the honest
    /// choice on macOS — the system font is too humanist for a silkscreen look. Falls back
    /// to the system face if it's ever unavailable.
    enum Font {
        private static let grotesque = "Helvetica Neue"

        /// Panel labels: small, uppercase, tightly tracked. Pair with `.silkscreenTracking`
        /// and uppercase the string — the font alone doesn't make the look.
        static let silkscreen = named(size: 9, weight: .medium)
        /// A slightly larger silkscreen label, for section headers on the panel.
        static let silkscreenLarge = named(size: 11, weight: .medium)

        static let caption = named(size: 10, weight: .regular)
        static let label = named(size: 11, weight: .regular)
        static let body = named(size: 13, weight: .regular)
        static let bodyEmphasis = named(size: 13, weight: .medium)
        static let title = named(size: 17, weight: .semibold)

        /// Readouts and timings. Monospaced so digits don't shift as they tick.
        static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        /// The big transport counter.
        static let counterLarge = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced)
            .monospacedDigit()

        /// Letter spacing for silkscreen labels, in points.
        static let silkscreenTracking: CGFloat = 1.1

        private static func named(size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .custom(grotesque, size: size).weight(weight)
        }
    }

    // MARK: - Spacing

    /// A 4pt grid. Panels are laid out on it; nothing sits between steps.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let panel: CGFloat = 32
    }

    // MARK: - Radius

    /// Small by design. Equipment has hard edges; anything soft reads as software.
    enum Radius {
        /// Seams and dividers — square.
        static let none: CGFloat = 0
        /// Indicator chips, small lamps.
        static let chip: CGFloat = 2
        /// Button caps and controls.
        static let control: CGFloat = 3
        /// Recessed wells and grouped panels.
        static let panel: CGFloat = 5
        /// The window itself.
        static let window: CGFloat = 8
    }

    // MARK: - Border

    enum Border {
        /// A drawn hairline. Not scaled — 1pt reads as a machined edge at any density.
        static let hairline: CGFloat = 1
        /// The seam between two panels, drawn in `Color.seam`.
        static let seam: CGFloat = 1
        /// Bevel thickness on raised controls.
        static let bevel: CGFloat = 1
    }

    // MARK: - Elevation

    /// Depth is physical: a raised cap casts a short hard shadow, a well is cut into the
    /// panel. No soft ambient glows.
    enum Shadow {
        /// A button cap sitting proud of the panel.
        static let raised = Spec(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        /// A cap while pressed — nearly flush.
        static let pressed = Spec(color: .black.opacity(0.22), radius: 1, x: 0, y: 0)
        /// A grouped panel above the chassis.
        static let panel = Spec(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        /// The window against the desktop.
        static let window = Spec(color: .black.opacity(0.30), radius: 24, x: 0, y: 8)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    /// Mechanical, not bouncy. A key travels and stops; it doesn't spring.
    enum Motion {
        /// Key travel down. Fast enough to feel like contact.
        static let press = Animation.easeOut(duration: 0.06)
        /// Key travel up.
        static let release = Animation.easeOut(duration: 0.12)
        /// Panel and view changes.
        static let panel = Animation.easeInOut(duration: 0.18)
        /// The record lamp coming on — instant, like a filament.
        static let lamp = Animation.easeOut(duration: 0.08)

        /// VU ballistics. A real VU meter reaches 99% of a step in ~300ms and overshoots
        /// slightly; that lag *is* the instrument's character, so the needle is damped
        /// rather than tracking the signal directly.
        static let needleAttack: TimeInterval = 0.30
        static let needleRelease: TimeInterval = 0.42
        /// Peak overshoot as a fraction of the step, before settling.
        static let needleOvershoot: Double = 0.06
    }
}

// MARK: - Hex helpers

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
