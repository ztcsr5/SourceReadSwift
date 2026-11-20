// Adapted from Yuedu-reader DeviceIdentity.swift, commit cbb9a6a5d59933ecaf42c651d7f9583a34925cd1.
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// See docs/licenses/Yuedu-reader-MPL-2.0.txt.
import CryptoKit
import Foundation
import os
import UIKit

/// Captures the vendor identifier on the main actor for synchronous source scripts.
enum SourceDeviceIdentity {
    private static let captured = OSAllocatedUnfairLock<String?>(initialState: nil)
    private static let fallbackID: String = {
        let key = "sourceDeviceIdentity.fallback"
        if let saved = UserDefaults.standard.string(forKey: key), UUID(uuidString: saved) != nil { return saved }
        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
    }()

    @MainActor
    static func captureAtLaunch() {
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? fallbackID
        captured.withLock { $0 = identifier }
    }

    static var vendorID: String {
        captured.withLock { $0 } ?? fallbackID
    }

    static var androidID: String { androidID(for: vendorID) }

    /// Android rules require 16 lowercase hex characters, unique to the captured device identity.
    static func androidID(for identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
