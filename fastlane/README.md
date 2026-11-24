# App Store texts

Store listing texts in fastlane's `deliver` layout, one file per App Store Connect field. Copy them into App Store Connect, or upload with `fastlane deliver` later.

- `metadata/<lang>/`: name, subtitle (≤ 30), promotional text (≤ 170), description (≤ 4000), keywords (≤ 100, comma separated, don't repeat words from name/subtitle), release notes, URLs
- `metadata/primary_category.txt`, `secondary_category.txt`, `copyright.txt`
- `metadata/review_information/`: contact and notes for App Review
- `testflight/<lang>.txt`: "What to Test" for the current TestFlight build (update per upload)

Languages: `de-DE`, `en-US`.
