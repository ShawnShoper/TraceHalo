import Foundation
import TraceHaloCore

enum MenuBarStatusLayout {
    static let minimumStatusItemWidth: CGFloat = 24
    static let statusItemHorizontalInset: CGFloat = 1

    private static let stripHorizontalPadding: CGFloat = 2
    private static let componentSpacing: CGFloat = 7
    private static let statusIconWidth: CGFloat = 15
    private static let verticalLabelWidth: CGFloat = 8
    private static let labelContentSpacing: CGFloat = 3
    private static let chartLabelSpacing: CGFloat = 2
    private static let chartWidthWithPadding: CGFloat = 40
    private static let gaugeWidth: CGFloat = 7

    static func visibleComponents(
        in configuration: MonitorConfiguration
    ) -> [MonitorStatusBarComponent] {
        configuration.statusBarComponents.filter(\.isVisible)
    }

    static func displayedComponents(
        in configuration: MonitorConfiguration
    ) -> [MonitorStatusBarComponent] {
        let visible = visibleComponents(in: configuration)
        switch configuration.statusBarLayoutMode {
        case .full:
            return visible
        case .compact:
            return Array(visible.prefix(1))
        case .iconOnly:
            return []
        }
    }

    static func showsStatusIcon(in configuration: MonitorConfiguration) -> Bool {
        configuration.statusBarLayoutMode == .iconOnly
            || configuration.showsStatusBarIcon
            || visibleComponents(in: configuration).isEmpty
    }

    static func estimatedContentWidth(for configuration: MonitorConfiguration) -> CGFloat {
        let components = displayedComponents(in: configuration)
        let includesIcon = showsStatusIcon(in: configuration)
        let elementCount = components.count + (includesIcon ? 1 : 0)
        let spacing = CGFloat(max(elementCount - 1, 0)) * componentSpacing
        let iconWidth = includesIcon ? statusIconWidth : 0
        let componentsWidth = components.reduce(CGFloat.zero) { partial, component in
            partial + componentWidth(component)
        }
        return stripHorizontalPadding + spacing + iconWidth + componentsWidth
    }

    static func estimatedStatusItemWidth(for configuration: MonitorConfiguration) -> CGFloat {
        max(
            minimumStatusItemWidth,
            ceil(estimatedContentWidth(for: configuration)) + statusItemHorizontalInset * 2
        )
    }

    static func valueWidth(for metric: MonitorMetric) -> CGFloat {
        switch metric {
        case .fanSpeed, .networkReceived, .networkSent, .uptime:
            48
        case .temperature:
            34
        default:
            32
        }
    }

    private static func componentWidth(_ component: MonitorStatusBarComponent) -> CGFloat {
        switch component.style {
        case .miniChart:
            verticalLabelWidth + chartLabelSpacing + chartWidthWithPadding
        case .value:
            verticalLabelWidth + labelContentSpacing + valueWidth(for: component.metric)
        case .verticalGaugeValue:
            verticalLabelWidth
                + labelContentSpacing
                + gaugeWidth
                + labelContentSpacing
                + valueWidth(for: component.metric)
        }
    }
}
