import SwiftUI

struct PlaceholderFeatureView: View {
    private let titleText: Text
    private let subtitleText: Text
    private let navigationTitleText: Text
    let systemImage: String
    private let showsNavigationChrome: Bool

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        showsNavigationChrome: Bool = true
    ) {
        self.titleText = Text(title)
        self.subtitleText = Text(subtitle)
        self.navigationTitleText = Text(title)
        self.systemImage = systemImage
        self.showsNavigationChrome = showsNavigationChrome
    }

    init(
        titleKey: LocalizedStringKey,
        subtitleKey: LocalizedStringKey,
        systemImage: String,
        showsNavigationChrome: Bool = true
    ) {
        self.titleText = Text(titleKey)
        self.subtitleText = Text(subtitleKey)
        self.navigationTitleText = Text(titleKey)
        self.systemImage = systemImage
        self.showsNavigationChrome = showsNavigationChrome
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationStack {
                    placeholderContent
                }
            } else {
                placeholderContent
            }
        }
    }

    private var placeholderContent: some View {
        ZStack {
            CalendarColor.groupedBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                titleText
                    .font(.title2.weight(.semibold))

                subtitleText
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(CalendarColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .modifier(NavigationChromeModifier(enabled: showsNavigationChrome, titleText: navigationTitleText))
    }
}

private struct NavigationChromeModifier: ViewModifier {
    let enabled: Bool
    let titleText: Text

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
