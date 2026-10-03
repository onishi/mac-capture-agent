import SwiftUI

/// Quiet, compact card: source language, original text, translation.
struct HUDView: View {
    let message: HUDMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble")
                    .imageScale(.small)
                Text(message.title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Text(message.original)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(message.detail)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.disabled)
        }
        .padding(14)
        .frame(width: HUDView.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(HUDView.shadowMargin)
        .accessibilityElement(children: .combine)
    }

    static let width: CGFloat = 320
    static let shadowMargin: CGFloat = 12
}
