import AppKit
import MielCore
import MielSystem

let usage = """
    mielwm: every window on one endless canvas, tiled like AeroSpace.

      mielwm                      run the app (menu bar)
      mielwm <action> [args]      tell the running app: overview, search [text], settings,
                                  help, switch next|prev, focus|nudge|pan left|right|up|down,
                                  workspace 1-9|next|prev, move-to-workspace 1-9,
                                  layout tiles|stack|floating, zoom in|out, fit, frame,
                                  summon, land, back, fill, fullscreen, pin, grow, shrink,
                                  arrange, undo, redo, refresh
      mielwm state                the running app's canvas as JSON
      mielwm quit                 quit the running app (every window back on a screen)
      mielwm snapshot --state desktop|overview|overview:<command>|search:<q>|switcher|help
                      [--real [--pid <pid>]] [--screen <n>] [--fake-external]
                      [--light | --dark] [--workspaces] [--time <s>]
                      [--reduce-transparency] [--increase-contrast] --out <file.png>
                                  render one state to a PNG, synthetic windows or (--real)
                                  yours; moves nothing. --fake-external adds a 1080p display
                                  to the right of the primary one; --light and --dark pick
                                  the appearance (default: the system's); --workspaces draws
                                  example workspace frames; --time stops the clock that many
                                  seconds in (default 4), to see a flight mid-way
      mielwm --list-windows [--json] [--fps] [--pid <pid>]
                                  the windows Accessibility and ScreenCaptureKit see (regular
                                  apps, or any app with --pid); moves nothing
      mielwm --settings-preview [--out <dir>] [--menu] [--selftest] [--live <pane>]
                                  save the Settings panes, the onboarding, About and the menu
                                  bar indicator as PNGs, light and dark; --menu also the open
                                  menu; --selftest drives the window's controls instead; --live
                                  keeps the window open 10 s. No canvas, moves nothing
                                  (development; the README has the rest)
      mielwm --overview-preview [--out <dir>] [--accessibility]
                                  save the overview's search, results, shortcuts, toast and
                                  switcher in each glass style, light and dark, as PNGs of the
                                  main display; covers the screen for a moment (development)
      mielwm --notice-preview [--out <dir>]
                                  save the on-screen notices (toast, workspace, stack) in each
                                  material, light and dark, as PNGs; shows them for a moment
                                  (development)
      mielwm --unpark             put every window parked in the last layout back on a screen
      mielwm --manage-only <pid>  manage only that app's windows, no shortcuts, no overlay (tests)
      mielwm --help

    """

let args = Array(CommandLine.arguments.dropFirst())

/// The app, in normal or manage-only mode. Never returns.
@MainActor
func runApp(_ mode: Mode) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if Bundle.main.bundleURL.pathExtension != "app" { app.applicationIconImage = appIcon() } // alerts show it
    let delegate = AppDelegate(mode: mode)
    app.delegate = delegate
    app.run()
    exit(0)
}

MainActor.assumeIsolated {
    switch args.first {
    case nil:
        runApp(.normal)
    case "--help", "-h":
        print(usage, terminator: "")
    case "--manage-only":
        guard args.count == 2, let pid = Int32(args[1]) else { fail("usage: mielwm --manage-only <pid>") }
        runApp(.manageOnly(pid))
    case "--list-windows":
        listWindows(json: args.contains("--json"), fps: args.contains("--fps"), pid: value("--pid", in: args).flatMap { Int32($0) })
    case "--settings-preview":
        settingsPreview(args)
    case "--overview-preview":
        overviewPreview(args)
    case "--notice-preview":
        noticePreview(args)
    case "--unpark":
        exit(unparkFromLayout() ? 0 : 1)
    case "--watch":
        guard args.count == 2, let pid = Int32(args[1]) else { fail("usage: mielwm --watch <pid>") }
        watch(pid)
    case "snapshot":
        snapshot(Array(args.dropFirst()))
    default:
        exit(send(args))
    }
}
