// Adapted from Yuedu-reader DeviceIdentity.swift, commit cbb9a6a5d59933ecaf42c651d7f9583a34925cd1.
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// See docs/licenses/Yuedu-reader-MPL-2.0.txt.
import os
import UIKit

/// Captures the vendor identifier on the main actor for synchronous source scripts.
enum SourceDeviceIdentity {
    private static let captured = OSAllocatedUnfairLock<String?>(initialState: nil)

    @MainActor
    static func captureAtLaunch() {
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? "ios-device"
        captured.withLock { $0 = identifier }
    }

    static var vendorID: String {
        captured.withLock { $0 } ?? "ios-device"
    }
}
