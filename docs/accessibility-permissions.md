# Accessibility permissions

`AXIsProcessTrusted()` is the source of truth for the running app. The setting
`hudReplacement` records the user's preference; a failed permission check must
never overwrite it. On login launches, missing permission suspends the event tap
until access is detected. Only an explicit permission button requests access.

`AXIsProcessTrustedWithOptions` prompts asynchronously. The app monitors for the
eventual result instead of treating the immediate result or a fixed 0.5-second
delay as a denial. Monitoring belongs to the application lifecycle, so closing
Settings or completing onboarding does not stop it.

## Signing and installed copies

For local development, select your team and **Apple Development** in Xcode's
Signing & Capabilities. Do not override the macOS identity with `-` (Sign to Run
Locally) when testing persistent permissions. Ad hoc signatures use a binary
hash as their designated requirement, which can change on every rebuild.

The Developer ID release pipeline overrides the signing identity explicitly.
Unsigned CI builds only check compilation and cannot verify persistent TCC grants.

An installed Developer ID build and a local development build can have the same
bundle identifier but different designated requirements. Always test grant,
quit, relaunch, and login with the same signed copy. The Restart action uses
`Bundle.main.bundleURL` so Launch Services cannot substitute another copy.

If System Settings shows access enabled but the app reports no access, check the
running path, signature, and TCC logs before assuming the app can repair it. The
app cannot switch the system permission off or grant it itself. A stale system
entry may need to be removed and the installed copy added again by the user.

## Verification

Run the standalone tests against the production permission controller:

```sh
swiftc -parse-as-library DynamicNotch/XPCHelperClient/AccessibilityAuthorization.swift \
  tests/accessibility_authorization_tests.swift -o /tmp/accessibility_authorization_tests
/tmp/accessibility_authorization_tests
```

Manual checks with a consistently signed installed build:

1. Grant access in onboarding, taking more than 0.5 seconds in System Settings.
   Onboarding advances once and HUD replacement starts.
2. Finish onboarding, quit, and relaunch through the login item. An existing
   grant works without prompting; an initial failed check preserves the HUD setting.
3. Open and close the HUD settings page. Grant or revoke system access while the
   page is closed. The event tap resumes or stops without changing the saved HUD preference.
4. Click the permission button repeatedly while access is missing. The system
   prompt appears once per process; subsequent clicks open System Settings.
5. Install another app copy with the same bundle identifier, then use Restart.
   Confirm that the running executable still comes from the original bundle.

References: [Apple's AXIsProcessTrustedWithOptions documentation](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
and [Apple DTS on stable signatures and TCC](https://developer.apple.com/forums/thread/663889).
