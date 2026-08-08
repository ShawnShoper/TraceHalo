import SwiftUI
import SystemScopeCore

struct PageHeader: View {
    @Environment(\.locale) private var locale
    let title: String
    let subtitle: String
    var symbol: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CalmTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    CalmTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(CalmTheme.strongHairline)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(localized(title))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CalmTheme.primaryText)
                Text(localized(subtitle))
                    .font(.system(size: 12.5))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)
            if let trailing { trailing }
        }
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}

struct SectionTitle: View {
    @Environment(\.locale) private var locale
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CalmTheme.accent)
                    .frame(width: 17)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(localized(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CalmTheme.primaryText)
                if let subtitle {
                    Text(localized(subtitle))
                        .font(.caption2)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            Spacer()
        }
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = CalmTheme.accent
    var fill = true

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                if fill, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.17), color.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let range = max(maximum - minimum, 0.001)
        let denominator = max(values.count - 1, 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(denominator) * size.width
            let normalized = (value - minimum) / range
            return CGPoint(x: x, y: size.height - CGFloat(normalized) * size.height)
        }
    }
}

struct RingGauge: View {
    @Environment(\.locale) private var locale
    let value: Double?
    let label: String
    var tint: Color = CalmTheme.accent
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) / 2 - 6
                var track = Path()
                track.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(track, with: .color(tint.opacity(0.15)), lineWidth: 7)

                if let value {
                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(max(value, 0), 1)),
                        clockwise: false
                    )
                    context.stroke(
                        arc,
                        with: .color(tint),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                }
            }
            VStack(spacing: 2) {
                Text(value.map { MetricFormatter.percent($0 * 100) } ?? "—")
                    .font(.system(size: size * 0.19, weight: .semibold, design: .rounded))
                    .foregroundStyle(CalmTheme.primaryText)
                    .monospacedDigit()
                Text(AppLocalization.string(label, defaultValue: label, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

struct DetailRow: View {
    @Environment(\.locale) private var locale
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 9) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 16)
            }
            Text(localized(label))
                .foregroundStyle(CalmTheme.secondaryText)
            Spacer()
            Text(localized(value))
                .fontWeight(.medium)
                .foregroundStyle(CalmTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func localized(_ text: String) -> String {
        AppLocalization.string(text, defaultValue: text, locale: locale)
    }
}

struct StatusPill: View {
    @Environment(\.locale) private var locale
    let text: String
    var color: Color = CalmTheme.mint
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(AppLocalization.string(text, defaultValue: text, locale: locale))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            color.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.16))
        }
    }
}

struct EmptyCapabilityView: View {
    @Environment(\.locale) private var locale
    let title: String
    let message: String
    var symbol = "questionmark.circle"

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(localized(title))
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            Text(localized(message))
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .calmCard()
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}

struct CalmDivider: View {
    var body: some View {
        Rectangle()
            .fill(CalmTheme.hairline)
            .frame(height: 1)
    }
}

extension CapabilityAvailability {
    var calmTitle: String {
        AppLocalization.currentString(rawCalmTitle)
    }

    private var rawCalmTitle: String {
        switch self {
        case .available: "可用"
        case .unavailable: "不可用"
        case .permissionRequired: "需要权限"
        case .failed: "读取失败"
        }
    }

    var calmColor: Color {
        switch self {
        case .available: CalmTheme.mint
        case .unavailable: .secondary
        case .permissionRequired: CalmTheme.amber
        case .failed: CalmTheme.rose
        }
    }
}
