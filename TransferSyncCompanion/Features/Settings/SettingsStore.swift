import Foundation
import ServiceManagement

@Observable
final class SettingsStore {
 var autoStackEnabled: Bool {
 get { UserDefaults.standard.object(forKey: "autoStackEnabled") as? Bool ?? true }
 set { UserDefaults.standard.set(newValue, forKey: "autoStackEnabled") }
 }

 var notificationsEnabled: Bool {
 get { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }
 set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
 }

 var launchAtLogin: Bool {
 get { SMAppService.mainApp.status == .enabled }
 set {
 do {
 if newValue {
 try SMAppService.mainApp.register()
 } else {
 try SMAppService.mainApp.unregister()
 }
 } catch {
 // Registration can fail silently - the getter will reflect actual state
 }
 }
 }
}
