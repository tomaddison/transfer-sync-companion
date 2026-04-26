import XCTest
@testable import TransferSyncCompanion

final class SettingsStoreTests: XCTestCase {

 private var sut: SettingsStore!

 override func setUp() {
 super.setUp()
 // Clean slate for each test
 UserDefaults.standard.removeObject(forKey: "autoStackEnabled")
 UserDefaults.standard.removeObject(forKey: "notificationsEnabled")
 sut = SettingsStore()
 }

 override func tearDown() {
 UserDefaults.standard.removeObject(forKey: "autoStackEnabled")
 UserDefaults.standard.removeObject(forKey: "notificationsEnabled")
 sut = nil
 super.tearDown()
 }

 // MARK: - autoStackEnabled

 func testAutoStackEnabled_defaultsToTrue() {
 XCTAssertTrue(sut.autoStackEnabled)
 }

 func testAutoStackEnabled_canBeDisabled() {
 sut.autoStackEnabled = false
 XCTAssertFalse(sut.autoStackEnabled)
 }

 func testAutoStackEnabled_persistsAcrossInstances() {
 sut.autoStackEnabled = false
 let sut2 = SettingsStore()
 XCTAssertFalse(sut2.autoStackEnabled)
 }

 func testAutoStackEnabled_canBeReEnabled() {
 sut.autoStackEnabled = false
 sut.autoStackEnabled = true
 XCTAssertTrue(sut.autoStackEnabled)
 }

 // MARK: - notificationsEnabled

 func testNotificationsEnabled_defaultsToTrue() {
 XCTAssertTrue(sut.notificationsEnabled)
 }

 func testNotificationsEnabled_canBeDisabled() {
 sut.notificationsEnabled = false
 XCTAssertFalse(sut.notificationsEnabled)
 }

 func testNotificationsEnabled_persistsAcrossInstances() {
 sut.notificationsEnabled = false
 let sut2 = SettingsStore()
 XCTAssertFalse(sut2.notificationsEnabled)
 }

 // MARK: - launchAtLogin

 func testLaunchAtLogin_readDoesNotCrash() {
 // SMAppService.mainApp.status may vary; just verify it doesn't crash
 _ = sut.launchAtLogin
 }

 // Note: We don't test the setter for launchAtLogin because
 // SMAppService.mainApp.register() requires a signed, sandboxed app
 // running as a real macOS application - it will fail in a test runner.
 // The getter is verified above; the setter is a simple try/catch wrapper.
}
