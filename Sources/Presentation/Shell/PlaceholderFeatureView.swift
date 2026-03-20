import SwiftUI

struct PlaceholderFeatureView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
