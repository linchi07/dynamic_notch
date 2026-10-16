//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

enum ApplicationRelauncher {
    static func restart() {
        let workspace = NSWorkspace.shared
        // A bundle-ID lookup can select a development copy with another signature.
        let appURL = Bundle.main.bundleURL

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: appURL, configuration: configuration, completionHandler: nil)

        NSApplication.shared.terminate(nil)
    }
}
