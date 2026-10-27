# Performance

`scripts/benchmark.sh` builds a release copy and measures it. The copy it
measures runs as a separate test instance with its own socket and settings,
managing 8 throwaway windows of 1200×800. Your own windows and a running mielwm
stay out of it. `scripts/benchmark.sh <bin dir>` measures another build
instead, so you can compare two. The table also goes to `build/benchmark.txt`.
The zoomed-out view shows on screen for about 15 seconds of the run.

CPU is the share of one core, wakeups are package idle wakeups per second, and
memory is the physical footprint. These are single runs on an M3 Pro with
macOS 27.0. The rows with playing windows move by about 2 points from one run
to the next.

## Numbers

"Before" is commit 14a6d6a, before any optimisation work. "Now" is commit
0c74a5c and later.

| Scenario                                 | Before CPU | Now CPU    | Before memory | Now memory |
|------------------------------------------|-----------:|-----------:|--------------:|-----------:|
| Idle, 30 s                               |      0.03% |      0.01% |       95.5 MB |    88.5 MB |
| Two workspace switches, 2 s              |      1.80% | 1.74 to 1.97% |       96.2 MB |    89.2 MB |
| Overview open, still windows, 10 s       |     20.51% |  3.5 to 4.2%  |      366.7 MB |   265.5 MB |
| Overview open, windows playing, 10 s     |  7.9 to 11.5% | 10.0 to 10.6% |      366.5 MB |   393.2 MB |
| Closing the overview, then 5 s           |      1.07% |  3.5 to 3.9%  |      237.3 MB |   265.5 MB |
| 45 s after closing                       |      0.03% |      0.01% |      237.1 MB |   183.1 MB |
| Launch to 8 windows managed              |  1.0 to 1.3 s |      1.5 s |               |            |

Most windows sit still most of the time, so the still-window row is the one
that matters day to day. It dropped by four fifths. Idle CPU is a third of
what it was, and 45 seconds after the overview closes mielwm holds 54 MB less,
because window pictures shrink to small stills.

Three rows got worse. Windows that repaint 60 times a second cost the same
CPU in the overview and about 27 MB more memory, and nobody has found where
those 27 MB go. Closing costs more for a few seconds, mostly because each live
picture is turned into a still.

## What made still windows expensive

On macOS 27, ScreenCaptureKit sends a window's picture again every time the
display redraws, marked as changed even when it isn't. mielwm took each one as
new and drew the overview again. That redraw made the display redraw, which
sent the picture again, about 57 times a second. mielwm now compares each new
picture with the one it holds, sampling every 8th row, and drops it when they
match. A stream that stays the same for 30 frames slows to 15 fps until two
frames in a row change.

The caret in the search field forced about 10 full redraws a second. It now
blinks in its own small Core Animation layer, the way macOS text fields do it.

The renderer used to keep the capture buffers of its last three frames.
ScreenCaptureKit gives each stream four, so once the overview stopped drawing,
a playing window's stream ran out and froze. Buffers now go back as soon as the
GPU is done with a frame. That fixed the freeze and saves the 127 MB in the
still-window row.

What's left with still windows is the display link waking the main thread 120
times a second, about 1.4%, and the check on each live stream at 15 fps.

## Offscreen measurements

These come from the optimisation pass, measured with the renderer drawing
offscreen.

| Scenario                                   | Before                 | After                   |
|--------------------------------------------|------------------------|-------------------------|
| Overview open, nothing changing, 10 s      | 1200 frames, 4.7 s GPU | 1 frame, 4 ms GPU       |
| Search field open, idle, 10 s              | 1200 frames, 6.0 s GPU | 81 frames, 0.35 s GPU   |
| 8 live window buffers after closing        | 118 MB                 | 2 MB                    |
| Stills of 15 windows on other workspaces   | 115 MB                 | 2 MB after 5 min hidden |
