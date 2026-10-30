# Performance

How much CPU and memory mielwm uses, and how to check it on your own Mac.

## At rest

Most of the time mielwm does nothing at all. There are no timers polling and nothing redrawing in the background, so between your actions it sits at about 0.01% of one CPU core and around 90 MB of memory. You won't find it in Activity Monitor's top list unless you go looking.

Switching workspaces or moving a window costs a short spike, about 1% of a core for the moment the windows move, then it drops back to rest.

## In the overview

The overview is the part that does real work. It shows a live picture of every window, so its cost depends on how much those windows change.

| While the overview is open | CPU | Memory |
| --- | ---: | ---: |
| Windows sitting still | about 1% | about 265 MB |
| Every window playing video | about 10% | about 395 MB |

Most windows sit still most of the time, so the first row is what you'll see day to day. A window that doesn't change costs almost nothing to show, and when nothing on screen changes the overview stops redrawing until something does. One playing video updates up to 60 times a second, and that's where the CPU goes.

When you close the overview, the live pictures turn into small stills. mielwm keeps those so the overview opens with pictures right away next time. Within a minute it's back to about 0.01% CPU and under 185 MB, and the stills of windows you haven't seen for a few minutes shrink further.

## With Barik

With [Work with Barik](aerospace.md#barik) on, Barik asks mielwm for your workspaces on a timer. How often depends on the Barik you use.

Barik Enhanced asks every 5 seconds, which costs nothing you'd notice. The original Barik asks ten times a second. Each answer is cheap, but at that pace the `aerospace` command adds up to about a fifth of a CPU core, plus whatever Barik spends on its side. If that matters to you, Barik Enhanced is the better pairing.

## Check it yourself

Open Activity Monitor, search for mielwm, and watch the CPU and Memory columns while you work. Memory is the physical footprint, so it grows with the number of windows the overview has pictures of.

The numbers on this page come from an M3 Pro on macOS 27, with 8 windows managed. Runs with playing video move by about 2 points from one try to the next. mielwm's repository has a benchmark script that measures all of this on a test copy, away from your own windows. [CONTRIBUTING.md](https://github.com/mielsense/mielwm/blob/main/CONTRIBUTING.md) explains how to run it.
