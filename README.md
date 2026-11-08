# Drift Scorecard

AI video tools often "drift": a clip starts out matching your picture, then the colors get stronger, the image gets darker, or the room behind the subject changes. Drift is easy to miss by eye when you are reviewing many clips.

Drift Scorecard measures it. Give it a reference picture and a video, and it checks the **start, middle and end** of the video against the picture, then reports **PASS** or **FAIL** against limits you choose.

See a finished report in [`example-report/report.html`](example-report/report.html). Download that file and open it in a browser.

For results from real AI-generated clips, see [the real-world test](PORTFOLIO.md).

## What it measures

| Measure | Plain meaning | How it is calculated |
|---|---|---|
| **Saturation** | How vivid the colors are | Average of (strongest color − weakest color) ÷ strongest color for each pixel, shown as a percent of the reference |
| **Brightness** | How light the picture is | Average of red, green and blue for each pixel, shown as a percent of the reference |
| **Background** | Whether the setting still looks the same | The top 35% of the frame is split into a 4 × 2 grid. Each square's mix of colors is compared with the same square in the reference, then the results are averaged |

For saturation and brightness, 100% means the same as the reference. For background, 100% means identical and 0% means nothing in common.

A video passes only if **all three frames pass all three measures**.

## What you need

- A Mac running macOS 12 or newer
- Apple's free Command Line Tools. If you don't have them, open the **Terminal** app and run the command below, then click Install.

```bash
xcode-select --install
```

Nothing else needs installing, and the tool works entirely on your computer. It does not upload anything or use AI credits.

## Try it

1. Open the **Terminal** app.
2. Type `cd ` (with a space after it), drag this folder onto the Terminal window, and press Return.
3. Make the practice videos. The first run takes about a minute because it builds the tool.

```bash
swift run --quiet make-samples
```

4. Score the video that should pass:

```bash
swift run --quiet drift-scorecard samples/reference.png samples/steady.mp4
```

5. Score a video that should fail because its colors drift:

```bash
swift run --quiet drift-scorecard samples/reference.png samples/color-drift.mp4
```

6. Open the full report, which includes the frames that were compared:

```bash
open drift-report/report.html
```

There is also `samples/background-drift.mp4`, where the room changes during the clip.

## Use your own files

Put the reference picture first and the video second. The easy way to enter a file's location is to drag the file onto the Terminal window.

```bash
swift run --quiet drift-scorecard my-picture.png my-video.mp4
```

Pictures can be PNG or JPEG. Videos can be MP4 or MOV.

Each run replaces the report in the `drift-report` folder. To keep reports separate, add `--out` and a new folder name:

```bash
swift run --quiet drift-scorecard my-picture.png my-video.mp4 --out report-for-clip-2
```

## Set your own limits

| Setting | What it controls | Default |
|---|---|---|
| `--saturation-min` | Lowest allowed saturation | 85 |
| `--saturation-max` | Highest allowed saturation | 115 |
| `--brightness-min` | Lowest allowed brightness | 90 |
| `--brightness-max` | Highest allowed brightness | 110 |
| `--background-min` | Lowest allowed background match | 70 |

For example, this is a stricter brightness check:

```bash
swift run --quiet drift-scorecard my-picture.png my-video.mp4 --brightness-min 95 --brightness-max 105
```

### Choosing good limits

The defaults are only starting points. A fair way to set your own:

1. Choose a clip you already consider good and score it against its reference.
2. Note its numbers. A good clip won't score exactly 100%, because animation and video compression change pixels.
3. Set your limits a little outside those numbers.
4. Use those limits on your other clips.

This matters most for videos from other tools. Video files store color differently from pictures, so a clip can be consistently a few percent off its reference even when it looks right. While building this tool, a practice video with no color label measured 83% saturation against its own source picture. Once the label was added, it measured 99.7%. Checking a known-good clip first shows you what "normal" looks like for your tool.

## Reading the result

The report is saved as `report.html` for people and `report.json` for other software.

The program also finishes with a status number that automated workflows can use:

| Status | Meaning |
|---|---|
| 0 | The video passed |
| 1 | The video failed |
| 2 | It could not run, such as a missing or damaged file |

## What it can't tell you

Treat the scorecard as a first filter, not a replacement for watching the clip.

- It compares overall color. It can't recognize whether a person, animal or object still looks like itself.
- It assumes the top 35% of the frame is mostly background. If your subject fills that area, or the camera moves on purpose, the background score will drop.
- It checks three moments, so a brief glitch between them won't be seen.
- The background check groups colors into broad ranges. A small shift that crosses from one range to another can change the score more than the eye would expect.

## Run the tests

```bash
swift run --quiet drift-tests
```

The tests check the math on known colors, the pass and fail rules, error handling and report writing. They also generate practice videos and confirm that steady footage passes and drifting footage fails. The last line should end with `0 failed`.

## How the code is organized

| Location | Purpose |
|---|---|
| `Sources/DriftCore/Metrics.swift` | The three measurements |
| `Sources/DriftCore/Scorecard.swift` | Limits, pass/fail rules and command-line options |
| `Sources/DriftCore/Media.swift` | Opening pictures and pulling frames from video |
| `Sources/DriftCore/Report.swift` | Terminal, HTML and JSON reports |
| `Sources/DriftCore/SampleMedia.swift` | Practice picture and videos |
| `Sources/drift-tests/main.swift` | The tests |
