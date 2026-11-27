import SwiftUI

// MARK: - Buttons

/// Capsule button used for primary page actions ("Play", "Shuffle").
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.ui(14, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background(
                    Capsule().fill(prominent ? Theme.accent : Color.white.opacity(hovering ? 0.16 : 0.1))
                )
                .overlay(Capsule().fill(Color.white.opacity(prominent && hovering ? 0.1 : 0)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Plain button that dims when pressed and brightens on hover.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Round accent play button shown on hovered artwork.
struct PlayCircleButton: View {
    var size: CGFloat = 44
    var isPlaying = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: isPlaying ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.accent))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .scaleEffect(hovering ? 1.07 : 1)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(isPlaying ? "Pause" : "Play")
    }
}

/// Circular translucent icon button (header actions, nav arrows).
struct CircleIconButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 15
    var isActive = false
    var isEnabled = true
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : (isEnabled ? Theme.primaryText : Theme.tertiaryText))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering && isEnabled ? 0.15 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Heart toggle.
struct FavoriteButton: View {
    let isFavorite: Bool
    var size: CGFloat = 14
    var inactiveColor: Color = Theme.secondaryText
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.accent : (hovering ? Theme.primaryText : inactiveColor))
                .contentTransition(.symbolEffect(.replace))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// Small transport-style icon button (player bar).
struct ControlButton: View {
    let systemImage: String
    var size: CGFloat = 16
    var isActive = false
    var isEnabled = true
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size + 16, height: size + 16)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isActive {
                        Circle().fill(Theme.accent).frame(width: 4, height: 4).offset(y: 3)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .help(help)
    }

    private var color: Color {
        if !isEnabled { return Theme.tertiaryText }
        if isActive { return Theme.accent }
        return hovering ? Theme.primaryText : Theme.secondaryText
    }
}

// MARK: - Text

/// Text that behaves like a link: underline + pointer on hover.
struct LinkText: View {
    let text: String
    var font: Font = .ui(12)
    var color: Color = Theme.secondaryText
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(hovering ? Theme.primaryText : color)
            .underline(hovering)
            .lineLimit(1)
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .pointerStyle(.link)
    }
}

struct QualityBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.ui(10.5, .semibold))
                .tracking(0.3)
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .lineLimit(1)
        .fixedSize()
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.display(20, .bold))
                .foregroundStyle(Theme.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.ui(13))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.plain)
                    .font(.ui(12.5, .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Page chrome

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.display(34, .bold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Horizontal text tabs with an animated accent underline.
struct TabStrip<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 30) {
            ForEach(tabs) { tab in
                TabStripItem(
                    title: title(tab),
                    isSelected: tab == selection,
                    namespace: namespace
                ) {
                    selection = tab
                }
            }
        }
        // Animate only the underline; the tab content swaps instantly instead of cross-fading two pages.
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

private struct TabStripItem: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.ui(14.5, isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected || hovering ? Theme.primaryText : Theme.secondaryText)
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Theme.accent)
                            .matchedGeometryEffect(id: "underline", in: namespace)
                    }
                }
                .frame(height: 2.5)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Rounded dropdown used for sort / filter options.
struct DropdownMenu<Content: View>: View {
    let label: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(label).font(.ui(12.5, .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.field))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Round "…" menu button.
struct MoreMenuButton<Content: View>: View {
    var size: CGFloat = 40
    var filled = true
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(hovering || filled ? Theme.primaryText : Theme.secondaryText)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Color.white.opacity(hovering ? 0.15 : 0.08) : .clear))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("More")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.bottom, 4)
            Text(title)
                .font(.display(20, .bold))
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.ui(13))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Animated "now playing" bars.
struct EqualizerBars: View {
    var isAnimating: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    let phase = Double(bar) * 1.7
                    let speed = 5.2 + Double(bar) * 1.9
                    let level = isAnimating ? 0.28 + 0.72 * abs(sin(t * speed / 2 + phase)) : [0.45, 0.8, 0.6][bar]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 3, height: max(2, height * level))
                }
            }
            .frame(width: 13, height: height, alignment: .bottom)
        }
    }
}

/// Lets the user drag the window from custom chrome areas (the title bar is hidden).
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .onTapGesture(count: 2) {
                NSApp.keyWindow?.zoom(nil)
            }
    }
}
