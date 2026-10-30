# Window rules

Float a window or send it to a workspace by its app's name, its bundle id or its title, like AeroSpace's `on-window-detected`.

## Writing a rule

Window rules live in the [configuration file](configuration.md), under `rules`. Give each rule a name and the fields it needs:

```json
{
  "rules": {
    "firefox-pip": { "app_id": "org.mozilla.firefox", "title": "Picture-in-Picture", "floating": true },
    "zoom": { "app": "^zoom", "workspace": 3 }
  }
}
```

Save the file and the rules apply to the next window that opens. Settings doesn't edit window rules, so they live only in the file. For a whole app, the lists in Settings > Windows are simpler. See [Floating windows](floating.md).

## Fields

| Field | Type | What it does |
| --- | --- | --- |
| `app` | text | A regular expression found anywhere in the app's name, ignoring case. |
| `title` | text | The same, for the window's title. |
| `app_id` | text | The app's bundle id, exactly, ignoring case. |
| `floating` | `true` or `false` | `true` makes the window float. |
| `workspace` | `1` to `9` | The window opens on that workspace. |

`app`, `title` and `app_id` are matchers. `floating` and `workspace` are what the rule does.

`mielwm --list-windows` prints every window's app name and title, the text `app` and `title` search. For a bundle id, point at the app in a list in Settings > Windows and the id shows, or run `osascript -e 'id of app "Firefox"'`.

## Which rule wins

- A window has to match every matcher a rule has.
- A rule with no matcher, or with neither `floating` nor `workspace`, does nothing and never hides a later rule.
- When several rules match, the first by name wins, with numbers in order, so `rule-2` comes before `rule-10`.
- Rules apply when a window first appears, so a title that changes later doesn't move it.

A rule wins over the other settings. Its `workspace` sends the window there even when the app is in Floating apps or new windows float, and it comes before Workspace rules. A rule with `floating` floats the window where it opened. If it also names a workspace, the workspace is ignored.

## Flat keys

Each field can also be its own key, `rules:<name>:<field>`:

```json
{
  "rules:firefox-pip:app_id": "org.mozilla.firefox",
  "rules:firefox-pip:title": "Picture-in-Picture",
  "rules:firefox-pip:floating": true
}
```

A pattern that isn't a valid regular expression, or a field with the wrong type, is listed as an error in Settings > Advanced and skipped. The rest of the rule still loads.

## From AeroSpace

[Import your config](import.md) turns AeroSpace's `[[on-window-detected]]` blocks into rules:

| AeroSpace | Becomes |
| --- | --- |
| `if.app-id` with `run = "move-node-to-workspace N"` | An app in Settings > Windows > Workspace rules. |
| `if.app-id` with `run = "layout floating"` | An app in Settings > Windows > Floating apps. |
| `if.app-name-regex-substring` | A rule with `app`. |
| `if.window-title-regex-substring` | A rule with `title`. |

Importing again replaces the rules an earlier import added. Rules you wrote yourself stay.
