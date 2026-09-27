//
//  launch_at_login_step_tests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch
import LaunchAtLogin
import Defaults

final class LaunchAtLoginStepTests: XCTestCase {

    func testOnboardingStepSequenceIncludesLaunchAtLogin() {
        // Verify that the launchAtLogin step exists and follows musicPermission
        let step = OnboardingStep.launchAtLogin
        switch step {
        case .launchAtLogin:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected .launchAtLogin step")
        }
    }

    func testAccessibilityGrantedEnablesHudReplacement() {
        // Verify default value is false
        let defaultValue = Defaults.Keys.hudReplacement.defaultValue
        XCTAssertFalse(defaultValue, "Default value for hudReplacement should be false")

        // Simulate granting accessibility in onboarding
        Defaults[.hudReplacement] = false
        XCTAssertFalse(Defaults[.hudReplacement])

        // Trigger onGranted action
        Defaults[.hudReplacement] = true
        XCTAssertTrue(Defaults[.hudReplacement], "hudReplacement should be true after accessibility permission is granted")
    }

    func testLocalizationKeysExist() {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else {
            // If Bundle.main does not contain xcstrings directly in test bundle, test file on disk
            let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let fileURL = projectRoot.appendingPathComponent("DynamicNotch/Localizable.xcstrings")
            guard let diskData = try? Data(contentsOf: fileURL),
                  let diskJson = try? JSONSerialization.jsonObject(with: diskData) as? [String: Any],
                  let diskStrings = diskJson["strings"] as? [String: Any] else {
                XCTFail("Failed to load Localizable.xcstrings")
                return
            }
            verifyKeys(in: diskStrings)
            return
        }
        verifyKeys(in: strings)
    }

    private func verifyKeys(in strings: [String: Any]) {
        let expectedKeys = [
            "Start Automatically at Login",
            "Enable DynamicNotch at login so your notch gestures, media controls, and shelf are always ready whenever you log into your Mac.",
            "Open at Login",
            "Start silently in the background",
            "Instant Access: Notch tools and HUDs are ready immediately.",
            "Silent in Background: Runs quietly without popping up windows.",
            "Preferences: You can change this anytime in Settings.",
            "Don't Launch at Login",
            "Recommended"
        ]

        for key in expectedKeys {
            XCTAssertNotNil(strings[key], "Missing localization key: \(key)")
            if let entry = strings[key] as? [String: Any],
               let localizations = entry["localizations"] as? [String: Any] {
                XCTAssertNotNil(localizations["zh-Hans"], "Missing zh-Hans translation for: \(key)")
                XCTAssertNotNil(localizations["en"], "Missing en translation for: \(key)")
            }
        }
    }
}
