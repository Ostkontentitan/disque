import SwiftUI

struct TopBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 8) {
            CircleIconButton(systemImage: "chevron.left", size: 32, iconSize: 13, isEnabled: router.canGoBack, help: "Back") {
                router.back()
            }
            CircleIconButton(systemImage: "chevron.right", size: 32, iconSize: 13, isEnabled: router.canGoForward, help: "Forward") {
                router.goForward()
            }
            SearchField()
                .frame(width: 360)
                .padding(.leading, 10)
            Spacer(minLength: 20)
            CircleIconButton(
                systemImage: "list.bullet",
                size: 32,
                iconSize: 13,
                isActive: router.showQueue,
                help: router.showQueue ? "Hide Queue" : "Show Queue"
            ) {
                router.showQueue.toggle()
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .frame(height: 68)
        .background { WindowDragArea() }
    }
}

private struct SearchField: View {
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focused ? Theme.primaryText : Theme.secondaryText)
            TextField("Search artists, albums, tracks", text: $router.searchText)
                .textFieldStyle(.plain)
                .font(.ui(13.5))
                .focused($focused)
                .onKeyPress(.escape) {
                    router.searchText = ""
                    focused = false
                    return .handled
                }
            if !router.searchText.isEmpty {
                Button {
                    router.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(focused ? Color.white.opacity(0.12) : Theme.field))
        .overlay(Capsule().strokeBorder(focused ? Color.white.opacity(0.25) : .clear, lineWidth: 1))
        .onChange(of: router.searchFocusToken) { _, _ in focused = true }
        .onChange(of: router.searchText) { _, _ in router.searchTextChanged() }
    }
}
