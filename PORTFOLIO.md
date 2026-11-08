# Drift Scorecard: real-world test

AI video can look right in the first frame, then slowly move away from the look of the series. I built Drift Scorecard to measure that automatically. It compares the start, middle and end of each clip with a reference picture, then gives a pass or fail against set limits.

## The test

I ran it on all 31 clips from one episode of a real AI-generated video series, scored against the same reference picture. Then I compared each result with my own production decision: 4 clips were approved and 27 were marked for a redo.

| Limits | Approved clips that passed | Redo clips that failed | Agreement with my decisions |
|---|---|---|---|
| Default (background at least 70%) | 2 of 4 | 26 of 27 | 28 of 31 |
| Looser background (at least 60%) | 4 of 4 | 22 of 27 | 26 of 31 |

## What it showed

- **It caught the long slide in quality.** A run of later clips failed under either limit, matching the fading and changed settings in my production notes.
- **Agreement alone is not enough.** Marking every clip for a redo would score 27 of 31, because most clips were redos. On the default limits, the tool beats that blunt rule by only one clip, and it rejected two approved clips.
- **Changing a limit has a cost.** Lowering the background limit to 60% accepted every approved clip, but also let five redo clips through.
- **Those misses show what to build next.** The five clips were rejected mostly for problems this version can't see, such as objects or characters changing shape or appearance.
- **File handling can look like drift.** During development, a test video with no color label measured 83% saturation against its own source picture. With the correct label it measured 99.7%, so I fixed the test video rather than loosening the limits.

## Limits of this test

This is one episode from one creator, with only four approved clips. Some redo decisions used earlier color and background checks that work much like this tool, so the comparison isn't fully independent. The approved clips were also re-rendered later than the others, which may affect their scores. The tool measures color and background match only, so a person still needs to review each clip.
