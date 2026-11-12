import SwiftUI

struct ProfileHeading: View {
    @ScaledMetric(relativeTo: .title) private var fontSize = 30.0
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ProfileMenuRow: View {
    let title: String
    let subtitle: String
    var icon = "chevron.right"

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct ProfileChoiceRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = 14.0
    let title: String
    let isSelected: Bool
    var isSingleChoice = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                selectionMark
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var selectionMark: some View {
        let surface = Color(.secondarySystemGroupedBackground)
        let tint = profileActionColor(in: colorScheme)

        if isSingleChoice {
            Circle()
                .fill(surface)
                .strokeBorder(isSelected ? tint : Color.secondary, lineWidth: 1)
                .overlay {
                    if isSelected {
                        Circle().fill(tint).frame(width: 10, height: 10)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? tint : surface)
                .strokeBorder(isSelected ? tint : Color.secondary, lineWidth: 1)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(profileActionLabelColor(in: colorScheme))
                    }
                }
        }
    }
}

struct ProfileNotice: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                Text(message)
                    .font(.footnote)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(colorScheme == .dark ? Color.orange : Color(red: 0.522, green: 0.353, blue: 0.094))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: 100, alignment: .topLeading)
        .background(
            colorScheme == .dark ? Color.orange.opacity(0.12) : Color(red: 0.980, green: 0.933, blue: 0.843),
            in: .rect(cornerRadius: 20)
        )
        .accessibilityElement(children: .combine)
    }
}

struct ProfileSaveButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = 14.0
    var title = "Сохранить"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(profileActionLabelColor(in: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(profileActionColor(in: colorScheme), in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private func profileActionColor(in colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? .accentColor : Color(red: 0.714, green: 0.298, blue: 0.208)
}

private func profileActionLabelColor(in colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? .black : .white
}
