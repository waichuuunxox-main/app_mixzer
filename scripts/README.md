# scripts

This folder contains helper scripts related to the project.

Note on the guidelines checker:

- The project now uses a Swift-native checker and a SwiftUI module:
  - CLI executable: `guidelines-check` (run with `swift run guidelines-check`).
  - SwiftUI view: `DocsConsistencyCheckerView` in the `GuidelinesUI` module.
- The Swift implementations remove the need for a Python runtime and external
  dependency (PyYAML).
- The legacy Python checker has been removed to avoid confusion. If you still
  need a copy, it can be recovered from the git history (or I can restore it
  into `scripts/legacy/` on request).

To run the Swift checker locally:

```bash
swift run guidelines-check
```

If you'd like the legacy script restored, tell me and I will add it back under
`scripts/legacy/` with a short note about needing PyYAML.
