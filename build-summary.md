# Build summary

Result: TEST FAILED

## Errors (0)

## Warnings (0)

## Other warnings (0)

## Test failures (11)
- /Users/runner/work/Photoeditor/Photoeditor/GradeUITests/GradeUITests.swift:46: error: -[GradeUITests.GradeUITests testAdjustAndSaveLook] : Failed to get matching snapshot: No matches found for Elements matching predicate '"adjust-grain" IN identifiers' from input {(
- Test Case '-[GradeUITests.GradeUITests testAdjustAndSaveLook]' failed (25.498 seconds).
- Test Suite 'All tests' failed at 2026-10-24 11:24:58.941.
- Test Suite 'GradeUITests' failed at 2026-10-24 11:24:58.938.
- Test Suite 'GradeUITests.xctest' failed at 2026-10-24 11:24:58.940.
- ━ Test "Finds the subject in the demo portrait (needs the Neural Engine or person segmentation)" recorded a known issue at UpscalerTests.swift:88:13: Expectation failed: (insights → PhotoInsights(pixelSize: (1600.0, 2400.0), faceCount: 1, hasSubject: false, noise: 0.45216695011604896, sharpness: 3.092075357741459, brightness: 0.30844268384741813, colourCast: 0.03262180846997664)).hasSubject → false
- ━ Test "Removing the background saves a transparent PNG" recorded a known issue at EditorModelTests.swift:240:17: Expectation failed: (model.insights → PhotoInsights(pixelSize: (1600.0, 2400.0), faceCount: 1, hasSubject: false, noise: 0.45216695011604896, sharpness: 3.092075357741459, brightness: 0.30844268384741813, colourCast: 0.03262180846997664)).hasSubject → false
- ◇ Test "A failed replace reports why" started.
- ◇ Test "A failed save reports why" started.
- ✔ Test "A failed replace reports why" passed after 6.349 seconds.
- ✔ Test "A failed save reports why" passed after 7.038 seconds.
