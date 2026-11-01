// Runs media key parsing and off-thread safety tests:
// swift -module-cache-path /tmp/swift-cache tests/media_key_interceptor_tests.swift -o /tmp/media_key_interceptor_tests
// /tmp/media_key_interceptor_tests

import AppKit
import CoreGraphics

struct MediaKeyInterceptorTests {
    private static let SYSTEM_DEFINED_EVENT_SUBTYPE_FIELD = CGEventField(rawValue: 83)
    private static let SYSTEM_DEFINED_EVENT_DATA1_FIELD = CGEventField(rawValue: 149)
    private static let SUBTYPE_AUX_CONTROL_BUTTONS: Int64 = 8
    static func run() {
        testMediaKeyParsing()
        testNonMediaKeyBypass()
        testBackgroundThreadSafety()
        print("PASS: media key parsing, non-media bypass, and off-thread safety tests succeeded")
    }

    /// Verifies parsing keycodes and states for all supported media keys.
    private static func testMediaKeyParsing() {
        let keyTypes = [0, 1, 2, 3, 7, 21, 22] // soundUp, soundDown, brightnessUp, brightnessDown, mute, kbUp, kbDown
        let states = [0xA, 0xB] // keyDown, keyUp

        guard let subtypeField = SYSTEM_DEFINED_EVENT_SUBTYPE_FIELD,
              let data1Field = SYSTEM_DEFINED_EVENT_DATA1_FIELD else {
            preconditionFailure("CGEventField constants must be valid")
        }

        for key in keyTypes {
            for state in states {
                let expectedData1 = (key << 16) | (state << 8)
                guard let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: expectedData1,
                    data2: -1
                ), let cgEvent = event.cgEvent else {
                    preconditionFailure("Failed to create mock media key event")
                }

                let subtype = cgEvent.getIntegerValueField(subtypeField)
                precondition(subtype == SUBTYPE_AUX_CONTROL_BUTTONS, "Subtype must be 8")

                let data1 = cgEvent.getIntegerValueField(data1Field)
                let parsedKey = (data1 & 0xFFFF_0000) >> 16
                let parsedState = (data1 & 0xFF00) >> 8

                precondition(parsedKey == Int64(key), "Key code must match expected key")
                precondition(parsedState == Int64(state), "State byte must match expected state")
            }
        }
    }

    /// Verifies that events with non-aux subtypes (such as input source or CapsLock events) are not treated as media keys.
    private static func testNonMediaKeyBypass() {
        guard let subtypeField = SYSTEM_DEFINED_EVENT_SUBTYPE_FIELD else {
            preconditionFailure("Subtype field constant must be valid")
        }

        // Subtypes other than 8 must be rejected by the subtype check
        let nonMediaSubtypes: [Int16] = [0, 1, 2, 3, 4, 16, 32]
        for sub in nonMediaSubtypes {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: sub,
                data1: 0,
                data2: 0
            ), let cgEvent = event.cgEvent else {
                preconditionFailure("Failed to create mock non-media event")
            }

            let subtype = cgEvent.getIntegerValueField(subtypeField)
            precondition(subtype != SUBTYPE_AUX_CONTROL_BUTTONS, "Non-media event must not have subtype 8")
        }
    }

    /// Verifies that reading CGEvent fields directly on a background thread does not trigger main-queue assertions.
    private static func testBackgroundThreadSafety() {
        let expectation = DispatchSemaphore(value: 0)
        var backgroundSuccess = false

        let thread = Thread {
            guard let subtypeField = SYSTEM_DEFINED_EVENT_SUBTYPE_FIELD,
                  let data1Field = SYSTEM_DEFINED_EVENT_DATA1_FIELD else {
                return
            }

            // Simulate incoming CapsLock-like flag changed or input method event
            let source = CGEventSource(stateID: .hidSystemState)
            if let capsEvent = CGEvent(keyboardEventSource: source, virtualKey: 57, keyDown: true) {
                capsEvent.flags = [.maskAlphaShift]

                // Direct CGEvent reading without NSEvent(cgEvent:)
                let subtype = capsEvent.getIntegerValueField(subtypeField)
                let data1 = capsEvent.getIntegerValueField(data1Field)
                precondition(subtype != SUBTYPE_AUX_CONTROL_BUTTONS, "CapsLock event must not match media subtype")
                _ = data1
            }

            // Simulate incoming media key event handled on background thread
            let expectedData1 = (0 << 16) | (0xA << 8)
            if let mediaEvent = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: expectedData1,
                data2: -1
            ), let cgEvent = mediaEvent.cgEvent {
                let subtype = cgEvent.getIntegerValueField(subtypeField)
                let data1 = cgEvent.getIntegerValueField(data1Field)
                precondition(subtype == SUBTYPE_AUX_CONTROL_BUTTONS, "Subtype must match")
                precondition(data1 == Int64(expectedData1), "Data1 must match")
            }

            backgroundSuccess = true
            expectation.signal()
        }

        thread.start()
        let result = expectation.wait(timeout: .now() + 2.0)
        precondition(result == .success && backgroundSuccess, "Background thread processing must succeed without crashing")
    }
}

MediaKeyInterceptorTests.run()
