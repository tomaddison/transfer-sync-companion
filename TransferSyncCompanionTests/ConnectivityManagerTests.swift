import XCTest
@testable import TransferSyncCompanion

@MainActor
final class ConnectivityManagerTests: XCTestCase {

    func testInitialState_isConnected() {
        let sut = ConnectivityManager()
        XCTAssertTrue(sut.isConnected, "Should default to connected before monitoring starts")
    }

    func testStartMonitoring_doesNotCrash() {
        let sut = ConnectivityManager()
        sut.startMonitoring()
        // NWPathMonitor runs on a background queue; just verify no crash
        sut.stopMonitoring()
    }

    func testStartMonitoring_staysConnectedOnWifi() async throws {
        let sut = ConnectivityManager()
        sut.startMonitoring()

        // Give the monitor time to fire its initial path update
        try await Task.sleep(for: .milliseconds(500))

        // On a development machine with network, this should be true
        XCTAssertTrue(sut.isConnected, "Should report connected on a machine with network access")

        sut.stopMonitoring()
    }
}
