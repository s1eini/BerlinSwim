fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios preview

```sh
[bundle exec] fastlane ios preview
```

Preview the store texts for 1.0.0, upload only after confirmation

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload store texts, URLs and categories for 1.0.0 (no binary, no screenshots, no submission)

### ios beta_status

```sh
[bundle exec] fastlane ios beta_status
```

Read-only: latest builds with processing/beta review state, and beta test information

### ios beta_info

```sh
[bundle exec] fastlane ios beta_info
```

Set TestFlight test information (beta description, feedback email, privacy URL) for de-DE and en-GB

### ios testflight_notes

```sh
[bundle exec] fastlane ios testflight_notes
```

Set 'What to Test' (de/en) on build 4 of 1.0.0

### ios groups

```sh
[bundle exec] fastlane ios groups
```

List the app's TestFlight groups (names must match exactly in the external lane)

### ios external

```sh
[bundle exec] fastlane ios external
```

Give build 4 of 1.0.0 to the TestFlight group 'Extern' (submits for beta review if needed)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
