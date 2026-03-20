import SwiftUI

struct PlaceholderFeatureView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    private let showsNavigationChrome: Bool

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        showsNavigationChrome: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
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

                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
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
        .modifier(NavigationChromeModifier(enabled: showsNavigationChrome, title: title))
    }
}

private struct NavigationChromeModifier: ViewModifier {
    let enabled: Bool
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
