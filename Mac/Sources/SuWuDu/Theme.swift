import SwiftUI

// Shared with the Windows App.xaml celadon palette.
enum PetTheme {
    static let ink = Color(red: 40/255, green: 72/255, blue: 82/255)
    static let surface = Color(red: 240/255, green: 246/255, blue: 245/255)
    static let card = Color(red: 251/255, green: 253/255, blue: 252/255)
    static let border = Color(red: 184/255, green: 210/255, blue: 207/255)
    static let muted = Color(red: 88/255, green: 119/255, blue: 122/255)
    static let accent = Color(red: 0, green: 113/255, blue: 117/255)
    static let soft = Color(red: 212/255, green: 231/255, blue: 228/255)
}

struct PetButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        AnimatedPetButton(configuration: configuration, primary: primary)
    }
}
private struct AnimatedPetButton: View {
    let configuration: ButtonStyle.Configuration
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private var active: Bool { hovered && enabled }
    private var fill: Color {
        if configuration.isPressed { return PetTheme.ink }
        return active ? Color(red: 41/255, green: 93/255, blue: 101/255) : primary ? PetTheme.accent : PetTheme.card
    }
    var body: some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(active || primary ? Color.white : PetTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active ? PetTheme.accent : Color.clear, lineWidth: 1)
                        .scaleEffect(active ? 1 : 0.7)
                    RoundedRectangle(cornerRadius: 6).fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary || active ? PetTheme.accent : PetTheme.border))
                        .scaleEffect(active ? 0.7 : 1)
                }
                .animation(reduceMotion ? nil : .timingCurve(0.25, 0, 0.3, 1, duration: 0.3), value: active)
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.42)
            .onHover { hovered = $0 }
    }
}
struct PetCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    init(_ title: String = "", @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty { Text(title).font(.system(size: 18, weight: .semibold)) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(PetTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(PetTheme.border))
    }
}
struct PetHeading: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).foregroundStyle(PetTheme.muted)
            RoundedRectangle(cornerRadius: 2).fill(PetTheme.accent).frame(width: 46, height: 3).padding(.top, 5)
        }
    }
}
extension View {
    func petPage() -> some View {
        self.foregroundStyle(PetTheme.ink).tint(PetTheme.accent)
            .buttonStyle(PetButtonStyle()).textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PetTheme.surface).preferredColorScheme(.light)
    }
}

// Commit only fields edited in this window; pet position and menu changes may
// have changed while the settings window was open.
struct SettingsDraft {
    let original: Settings
    var value: Settings
    init(_ settings: Settings) { original = settings; value = settings }
    func applying(to current: Settings) -> Settings {
        var result = current
        func apply<T: Equatable>(_ path: WritableKeyPath<Settings, T>) {
            if value[keyPath: path] != original[keyPath: path] { result[keyPath: path] = value[keyPath: path] }
        }
        apply(\.petName); apply(\.skin); apply(\.scale); apply(\.topmost); apply(\.allSpaces)
        apply(\.wander); apply(\.wanderMin); apply(\.wanderMax); apply(\.hydration); apply(\.hydrationMinutes)
        apply(\.focusMinutes); apply(\.breakMinutes); apply(\.startSound); apply(\.finishSound); apply(\.breakSound)
        apply(\.microbreaks); apply(\.microMin); apply(\.microMax); apply(\.microSeconds)
        apply(\.microStartSound); apply(\.microEndSound); apply(\.provider); apply(\.apiModel)
        apply(\.codexModel); apply(\.reasoning); apply(\.memory); apply(\.screenVision)
        if value.skin != original.skin && value.petName == original.petName && ["苏无度", "沈青"].contains(original.petName) {
            result.petName = value.skin == "shenqing" ? "沈青" : "苏无度"
        }
        result.normalize()
        return result
    }
}
