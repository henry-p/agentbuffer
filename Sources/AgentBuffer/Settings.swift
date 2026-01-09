import Foundation

struct Settings {
    static let devForceSpinnerKey = "devForceSpinner"
    static let devQueueIconPercentKey = "devQueueIconPercent"
    static let devQueueIconOverrideEnabledKey = "devQueueIconOverrideEnabled"
    static let devSimulateAgentsKey = "devSimulateAgents"
    static let idleAlertThresholdKey = "idleAlertThresholdPercent"
    static let idleAlertSoundModeKey = "idleAlertSoundMode"
    static let idleAlertNotificationEnabledKey = "idleAlertNotificationEnabled"
    static let telemetryEnabledKey = "telemetryEnabled"
    static let devModeEnvironmentKey = "AGENTBUFFER_DEV"
    static let percentMin: Double = 0
    static let percentMax: Double = 100
    static let idleAlertDefaultThreshold: Double = 50
    static let idleAlertSoundModeDefault: IdleAlertSoundMode = .glass

    enum IdleAlertSoundMode: String {
        case off
        case glass
        case system
    }

    static var devModeEnabled: Bool {
        ProcessInfo.processInfo.environment[devModeEnvironmentKey] == "1"
    }

    static var devForceSpinner: Bool {
        get {
            UserDefaults.standard.bool(forKey: devForceSpinnerKey)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue, forKey: devForceSpinnerKey)
            }
        }
    }

    static var devQueueIconPercent: Double? {
        get {
            guard UserDefaults.standard.object(forKey: devQueueIconPercentKey) != nil else {
                return nil
            }
            let value = UserDefaults.standard.double(forKey: devQueueIconPercentKey)
            return clampPercent(value)
        }
        set {
            updateSetting {
                if let value = newValue {
                    UserDefaults.standard.set(clampPercent(value), forKey: devQueueIconPercentKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: devQueueIconPercentKey)
                }
            }
        }
    }

    static var devQueueIconOverrideEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: devQueueIconOverrideEnabledKey)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue, forKey: devQueueIconOverrideEnabledKey)
            }
        }
    }

    static var devSimulateAgents: Bool {
        get {
            UserDefaults.standard.bool(forKey: devSimulateAgentsKey)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue, forKey: devSimulateAgentsKey)
            }
        }
    }

    static var idleAlertThresholdPercent: Double {
        get {
            guard UserDefaults.standard.object(forKey: idleAlertThresholdKey) != nil else {
                return idleAlertDefaultThreshold
            }
            let value = UserDefaults.standard.double(forKey: idleAlertThresholdKey)
            return quantizePercent(value)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(quantizePercent(newValue), forKey: idleAlertThresholdKey)
            }
        }
    }

    static var idleAlertSoundMode: IdleAlertSoundMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: idleAlertSoundModeKey),
               let mode = IdleAlertSoundMode(rawValue: rawValue) {
                return mode
            }
            return idleAlertSoundModeDefault
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue.rawValue, forKey: idleAlertSoundModeKey)
            }
        }
    }

    static var idleAlertNotificationEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: idleAlertNotificationEnabledKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: idleAlertNotificationEnabledKey)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue, forKey: idleAlertNotificationEnabledKey)
            }
        }
    }

    static var telemetryEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: telemetryEnabledKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: telemetryEnabledKey)
        }
        set {
            updateSetting {
                UserDefaults.standard.set(newValue, forKey: telemetryEnabledKey)
            }
        }
    }

    static func clampPercent(_ value: Double) -> Double {
        min(max(value, percentMin), percentMax)
    }

    static func quantizePercent(_ value: Double) -> Double {
        floor(clampPercent(value))
    }

    private static func updateSetting(_ update: () -> Void) {
        update()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("AgentBuffer.settingsDidChange")
}
