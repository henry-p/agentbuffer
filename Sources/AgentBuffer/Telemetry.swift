import Foundation
import OpenPanel

enum Telemetry {
    private static let clientId = "cbe81f38-d04c-46b9-8ffa-b9a0c48499bd"
    private static let apiUrl = "https://proxy.analytics.vibeps.zereal.ai"
    private static var configured = false
    private static let alwaysAllowedEvents: Set<String> = [
        "telemetry.opt_in",
        "telemetry.opt_out"
    ]

    static func configure() {
        guard !configured else {
            return
        }
        configured = true
        let options = OpenPanel.Options(
            clientId: clientId,
            apiUrl: apiUrl,
            filter: { payload in
                if case .track(let trackPayload) = payload {
                    if alwaysAllowedEvents.contains(trackPayload.name) {
                        return true
                    }
                }
                return Settings.telemetryEnabled
            },
            automaticTracking: true
        )
        OpenPanel.initialize(options: options)
        OpenPanel.setGlobalProperties(globalProperties())
    }

    private static func globalProperties() -> [String: Any] {
        var properties: [String: Any] = [
            "app": "AgentBuffer",
            "platform": "macOS"
        ]
        let bundle = Bundle.main
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            properties["app_version"] = version
        }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            properties["app_build"] = build
        }
        let isAppBundle = bundle.bundleURL.pathExtension.lowercased() == "app"
            && (bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String) == "APPL"
        properties["app_mode"] = isAppBundle ? "bundle" : "dev"
        return properties
    }

    static func track(_ name: String, properties: [String: Any] = [:]) {
        guard configured else {
            return
        }
        OpenPanel.track(name: name, properties: properties)
    }

    static func trackOptChange(enabled: Bool) {
        let name = enabled ? "telemetry.opt_in" : "telemetry.opt_out"
        track(name, properties: ["enabled": enabled])
    }

    static func trackSettingToggle(_ setting: String, enabled: Bool) {
        track("settings.toggle_changed", properties: [
            "setting": setting,
            "enabled": enabled
        ])
    }

    static func trackSettingValue(_ setting: String, value: Double) {
        track("settings.value_changed", properties: [
            "setting": setting,
            "value": value
        ])
    }

    static func trackUi(_ name: String, properties: [String: Any] = [:]) {
        track(name, properties: properties)
    }

    static func trackState(_ name: String, properties: [String: Any] = [:]) {
        track(name, properties: properties)
    }
}
