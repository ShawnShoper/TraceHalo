import CoreWLAN
import Foundation
import SystemConfiguration

struct NetworkLinkDetails: Equatable, Sendable {
    var transmitRateMbps: Double?
    var rssi: Int?
    var noise: Int?
}

/// CoreWLAN may cross process boundaries and can take materially longer than
/// reading byte counters from `getifaddrs`. The live service caches these link
/// details independently so network throughput can remain real time.
enum NetworkLinkDetailsReader {
    static func detailsByBSDInterface() -> [String: NetworkLinkDetails] {
        let interfaces = CWWiFiClient.shared().interfaces() ?? []
        return Dictionary(uniqueKeysWithValues: interfaces.compactMap { interface in
            guard let name = interface.interfaceName else { return nil }
            let transmitRate = interface.transmitRate()
            let rssi = Int(interface.rssiValue())
            let noise = Int(interface.noiseMeasurement())
            return (
                name,
                NetworkLinkDetails(
                    transmitRateMbps: transmitRate > 0 ? transmitRate : nil,
                    rssi: rssi == 0 ? nil : rssi,
                    noise: noise == 0 ? nil : noise
                )
            )
        })
    }
}

/// Maps BSD interface names to the human-readable hardware service names shown
/// in System Settings. Reading this catalog does not change network settings.
enum NetworkServiceNaming {
    static func namesByBSDInterface() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return [:]
        }

        var names: [String: String] = [:]
        for interface in interfaces {
            guard let BSDName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?

            if type == kSCNetworkInterfaceTypeIEEE80211 as String {
                names[BSDName] = "Wi-Fi"
            } else if type == kSCNetworkInterfaceTypeEthernet as String {
                names[BSDName] = localized?.isEmpty == false
                    ? localized
                    : TraceHaloLocalization.string(
                        "network.ethernet",
                        defaultValue: "Ethernet"
                    )
            } else if let localized, !localized.isEmpty {
                names[BSDName] = localized
            }
        }
        return names
    }
}
