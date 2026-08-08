import Foundation
import SwiftUI
import SystemScopeCore

typealias AppLanguagePreference = SystemScopeCore.AppLanguagePreference
typealias AppLanguageResolver = SystemScopeCore.AppLanguageResolver

enum AppLocalization {
    static func string(
        _ key: String,
        defaultValue: String,
        locale: Locale
    ) -> String {
        let localization = AppLanguageResolver.supportedIdentifier(
            for: locale.identifier
        ) ?? AppLanguageResolver.englishIdentifier
        let resourceLocalization = localization == AppLanguageResolver.simplifiedChineseIdentifier
            ? "zh-hans"
            : localization
        guard let localizationURL = packagedOrModuleResourceBundle.url(
            forResource: resourceLocalization,
            withExtension: "lproj"
        ), let localizedBundle = Bundle(url: localizationURL) else {
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
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(
                   "SystemScope_SystemScopeApp.bundle",
                   isDirectory: true
               )
           ) {
            return packagedBundle
        }
        return .module
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
