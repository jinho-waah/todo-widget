import SwiftUI

struct RemindersPermissionBanner: View {
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.systemRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(DesignTokens.systemRed.opacity(0.10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
