import Foundation
import SwiftUI
import TraceHaloCore

typealias AppLanguagePreference = TraceHaloCore.AppLanguagePreference
typealias AppLanguageResolver = TraceHaloCore.AppLanguageResolver

enum AppLocalization {
    static func string(
        _ key: String,
        defaultValue: String,
        locale: Locale
    ) -> String {
        let localization = AppLanguageResolver.supportedIdentifier(
            for: locale.identifier
        ) ?? AppLanguageResolver.englishIdentifier
        let resourceLocalizations = localization == AppLanguageResolver.simplifiedChineseIdentifier
            ? ["zh-hans", "zh-Hans"]
            : [localization]
        guard let localizationURL = resourceLocalizations.lazy.compactMap({
            packagedOrModuleResourceBundle.url(
                forResource: $0,
                withExtension: "lproj"
            )
        }).first,
        let localizedBundle = Bundle(url: localizationURL) else {
            return defaultValue
        }
        return localizedBundle.localizedString(
            forKey: key,
            value: defaultValue,
            table: nil
        )
    }

    /// See the Core resolver for why packaged apps must look in
    /// `Contents/Resources` before touching SwiftPM's generated accessor.
    private static var packagedOrModuleResourceBundle: Bundle {
#if SNAPSHOT_QA
        if let overridePath = ProcessInfo.processInfo.environment[
            "TRACEHALO_SNAPSHOT_APP_RESOURCE_BUNDLE"
        ], let overrideBundle = Bundle(path: overridePath) {
            return overrideBundle
        }
#endif
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(
                   "TraceHalo_TraceHaloApp.bundle",
                   isDirectory: true
               )
        ) {
            return packagedBundle
        }
#if SWIFT_PACKAGE
        return .module
#else
        return .main
#endif
    }
}

struct AppLanguageLocaleModifier: ViewModifier {
    @AppStorage(AppLanguagePreference.storageKey)
    private var storedPreference = AppLanguagePreference.defaultValue.rawValue
    @State private var systemLocaleRevision = 0

    func body(content: Content) -> some View {
        content
            .environment(\.locale, resolvedLocale)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSLocale.currentLocaleDidChangeNotification
                )
            ) { _ in
                systemLocaleRevision &+= 1
            }
    }

    private var resolvedLocale: Locale {
        _ = systemLocaleRevision
        return AppLanguageResolver.resolvedLocale(
            for: AppLanguagePreference.storedPreference(from: storedPreference)
        )
    }
}

extension View {
    func traceHaloLanguageEnvironment() -> some View {
        modifier(AppLanguageLocaleModifier())
    }
}
