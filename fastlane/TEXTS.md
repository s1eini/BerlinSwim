# App Store texts

Store listing texts in fastlane's `deliver` layout, one file per App Store Connect field. Copy them into App Store Connect, or upload with `fastlane deliver` later.

- `metadata/<lang>/`: name, subtitle (≤ 30), promotional text (≤ 170), description (≤ 4000), keywords (≤ 100, comma separated, don't repeat words from name/subtitle), URLs
- `metadata/primary_category.txt`, `secondary_category.txt`, `copyright.txt`
- `review/`: App Review contact (name, email) and notes; the phone number comes from `ASC_REVIEW_PHONE` in `fastlane/.env`
- `testflight/<lang>.txt`: "What to Test" for the current TestFlight build (update per upload)

Languages: `de-DE`, `en-GB` (must match the languages set up in App Store Connect, otherwise deliver adds a new one).

## Upload

One-time setup: `brew install fastlane`, create an App Store Connect API key (role App Manager), copy `fastlane/.env.example` to `fastlane/.env` and fill in Key ID, Issuer ID and the path to the `.p8` file (outside the repo).

Run from the repository root:

- `fastlane preview`: HTML preview of what would be uploaded; uploads only after you confirm
- `fastlane metadata`: upload texts, URLs and categories to the version in "Prepare for Submission" (no binary, no screenshots, no submission)
- `fastlane beta_info`: TestFlight test information (beta description from `testflight/beta_description/`, feedback email, privacy URL) for de-DE and en-GB
- `fastlane beta_status`: read-only overview of the latest builds, beta review state and test information
- `fastlane external`: give the current build to the TestFlight group "Extern" with the What to Test notes (submits for beta review if needed)
- `fastlane groups`: list TestFlight groups and their latest builds (group names in the external lane must match exactly)
- `fastlane testflight_notes`: set "What to Test" for the current build (version/build from `ios/project.yml`)

Edit texts here, not in App Store Connect: the next upload overwrites manual changes.

`release_notes.txt` ("What's New") is left out on purpose: App Store Connect has no such field for the first version. Add it per language from version 1.1 on.
