# 0001. One pure reducer

Accepted. Recorded October 2026.

## Context

A window manager reacts to a stream of events it doesn't control. Accessibility reports windows appearing, moving and closing, sometimes late and sometimes out of order. Keys, swipes, display changes and commands over the socket arrive at the same time. Testing that logic against real windows is slow, it flakes, and on a developer's own Mac it can scramble the windows they're working in.

## Decision

All of mielwm's state lives in one value, `CanvasState`, in `MielCore`. One function, `reduce(_:_:)` in [Reducer.swift](../Sources/MielCore/Reducer.swift), takes that state and one input and returns the next state and the window moves to make. `MielCore` imports no AppKit and touches no windows, timers or clock. The app reads macOS, feeds inputs in, and carries the moves out. Time arrives as an input too, `.tick(seconds)`.

## Consequences

- Most tests build a state, send it inputs and check the moves that come out. They need no windows, no permissions and no waiting, so they run in seconds on any Mac and on CI.
- The same input always gives the same result, so a bug report's steps become a test.
- The app can try an input on a copy of the state before it commits to it. `Controller.input` does this to wait for fresh window pictures before the overlay opens.
- Core never sees the real window, only what macOS last reported. A move it asked for counts once Accessibility reports the new frame, as a new input.
- Everything outside Core has to be translated into inputs and commands. A feature that needs something from macOS adds a case to `SystemEvent` or `WindowCommand` first.
- Core can't start timers, so it says when it next needs a tick, and the app schedules one. When nothing animates, mielwm gets no ticks and uses no CPU.
