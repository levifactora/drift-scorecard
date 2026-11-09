# Drift Scorecard: real-world test

AI video can look right in the first frame, then slowly move away from the look of the series. I built Drift Scorecard to measure that automatically. It compares frames from each clip with a reference picture, then scores them against set limits.

## The test

**Read this first:** the numbers in the first two tables overstate what the tool can do, because every clip was compared with one shared picture. The retest further down, using each clip's own start picture, is the fairer result.

I ran it on all 31 clips from one episode of a real AI-generated video series, scored against the same reference picture. Then I compared each result with my own production decision: 4 clips were approved and 27 were marked for a redo.

| Limits | Approved clips that passed | Redo clips that failed | Agreement with my decisions |
|---|---|---|---|
| Default (background at least 70%) | 2 of 4 | 26 of 27 | 28 of 31 |
| Looser background (at least 60%) | 4 of 4 | 22 of 27 | 26 of 31 |

## Version 2 on the same clips

Version 2 added an overall-look score, five frames per clip instead of three, and an UNSURE result for clips just outside a limit.

| Limits | Approved clips | Redo clips | Clearly right | Clearly wrong | Left to a person |
|---|---|---|---|---|---|
| Standard | 2 passed, 1 unsure, 1 failed | 24 failed, 2 unsure, 1 passed | 26 of 31 | 2 of 31 | 3 of 31 |
| Cartoon preset | 4 passed | 24 failed, 3 passed | 28 of 31 | 3 of 31 | 0 of 31 |

The UNSURE result reduced clear mistakes from 3 to 2 on standard limits by sending borderline clips to a person. Checking more frames, and adding overall look at its standard limit, did not change any result on this episode. The cartoon preset's limits were chosen after seeing these clips, so its row is a best case and still needs a test on new footage.

## Retest with each clip's own start picture

One shared picture is an unfair test: a clip from a different scene can fail just for being a different scene. So I retested the same 31 clips against each clip's own start picture, in a version that isn't released yet. The opening frames now closely matched their pictures, which confirms the pairing.

| Limits | Approved clips | Redo clips | Clearly right | Clearly wrong | Left to a person |
|---|---|---|---|---|---|
| Standard | 3 passed, 1 unsure | 17 passed, 10 failed | 13 of 31 | 17 of 31 | 1 of 31 |
| Cartoon preset | 4 passed | 17 passed, 10 failed | 14 of 31 | 17 of 31 | 0 of 31 |

No approved clip failed, which is the improvement I wanted. But 17 of the 27 redo clips passed. The earlier scores looked strong largely because most clips differed from the one shared picture, and most clips also happened to be redos. Part of those failures measured a change of scene, not drift.

I have not yet confirmed why each of those 17 clips was redone. My best explanation is that many had problems this tool can't see, such as characters, hands or objects going wrong. The limits were also set using one shared picture and haven't been re-tuned.

**What the tool is, based on this:** a measurement of color, brightness, background and general resemblance against a start picture. It is not a judge of whether a clip is good.

## What it showed

- **One shared picture can't separate drift from a change of scene.** With a shared picture, a run of later clips failed. Against their own start pictures, most of the redo clips passed.
- **Agreement alone is not enough.** Marking every clip for a redo would score 27 of 31, because most clips were redos. On the default limits, the tool beats that blunt rule by only one clip, and it rejected two approved clips.
- **Changing a limit has a cost.** Lowering the background limit to 60% accepted every approved clip, but also let five redo clips through.
- **Those misses show what to build next.** The five clips were rejected mostly for problems this version can't see, such as objects or characters changing shape or appearance.
- **File handling can look like drift.** During development, a test video with no color label measured 83% saturation against its own source picture. With the correct label it measured 99.7%, so I fixed the test video rather than loosening the limits.

## Limits of this test

This is one episode from one creator, with only four approved clips, so none of these numbers should be read as general accuracy. Some redo decisions used earlier color and background checks that work much like this tool, so the comparison isn't fully independent. The approved clips were also re-rendered later than the others, which may affect their scores. The tool measures color, background and general resemblance only, so a person still needs to review each clip.
