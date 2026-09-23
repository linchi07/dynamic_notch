# Security Policy

## Supported Versions

Security fixes are issued for the latest released version of Dynamic Notch. Please
upgrade to the newest release before reporting an issue.

| Version | Supported |
| ------- | --------- |
| 1.2.x   | ✅        |
| < 1.2   | ❌        |

## Reporting a Vulnerability

We take security bugs in Dynamic Notch seriously. We appreciate your efforts to
responsibly disclose your findings, and will make every effort to acknowledge your
contributions.

To report a security issue, please use the GitHub Security Advisory
["Report a Vulnerability"](https://github.com/linchi07/dynamic_notch/security/advisories/new)
tab. Please do **not** open a public issue for security problems.

You will receive a response indicating the next steps in handling your report. After
the initial reply, we will keep you informed of the progress towards a fix and full
announcement, and may ask for additional information or guidance.

Please give us a reasonable amount of time to resolve the issue before any public
disclosure.

## Scope

Dynamic Notch runs as a local macOS application with no server-side component. The
most relevant areas for security reports are:

- The local Unix domain socket used by third-party apps to post Live Activities
  (`ExternalLiveActivityServer`), including its peer-identity checks and the per-app
  permission model.
- The Sparkle update pipeline: EdDSA signature verification of update archives and
  the integrity of the update feed.
- Handling of untrusted input such as file paths from the Shelf, drag-and-drop
  payloads, and media metadata.

## Third-Party Dependencies

Report security bugs in third-party dependencies to the person or team maintaining
the package or dependency. The main runtime dependencies are Sparkle, Defaults,
KeyboardShortcuts, Lottie, and swiftui-introspect.
