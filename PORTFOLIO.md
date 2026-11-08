# Drift Scorecard: real-world test

AI video can look right in the first frame, then slowly move away from the look of the series. I built Drift Scorecard to measure that automatically. It compares the start, middle and end of each clip with a reference picture, then gives a pass or fail against set limits.

## The test

I ran it on three clips from a real AI-generated video series, all scored against the same series reference picture. Before the test, my production notes already recorded two clips as approved and one as visibly faded.

| Clip | Production status | Saturation | Brightness | Background match | Score against default limits |
|---|---|---|---|---|---|
| A | Approved | 91–96% | 102–104% | 77% | Pass |
| B | Approved | 86–88% | About 100% | 64–65% | Fail (background only) |
| C | Recorded as faded | 56–57% | 84% | 35% | Fail (all three) |

Saturation and brightness are percentages of the reference, so 100% means the same as the reference. The ranges cover the three frames checked in each clip.

## What it showed

- **The measurements agreed with human review on the clear problem.** The faded clip scored far below both approved clips on saturation and background.
- **The first limits needed calibrating.** The default background limit of 70% rejected an approved clip. A limit of 60% accepts both approved clips and still rejects the faded one.
- **File handling can look like drift.** During development, a test video with no color label measured 83% saturation against its own source picture. With the correct label it measured 99.7%, so I fixed the test video rather than loosening the limits.

## Limits of this test

This was a small check on three clips, and the 60% limit was chosen after seeing those same clips, so it still needs testing on new footage. The tool measures color and background match. It can't confirm that a character still looks like the same character, so a person still needs to review the clip.
