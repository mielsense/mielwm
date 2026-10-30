# Stacks

A stack shows one window at a time at full size, like AeroSpace's accordion, with a strip that tells you where you are.

## Making a stack

`⌥,` stacks the workspace you're on, and `⌥,` again goes back to tiles. To make every new workspace a stack, pick Stack under Settings > Layout > New windows.

A stack keeps the same gaps as tiles. Zoomed out in the [overview](overview.md), it looks like a fanned deck of cards.

## Moving through a stack

| Keys | What it does |
| --- | --- |
| `⌥←`, `⌥→` | The previous or next window in the stack. |
| `⌥Tab`, `⌥⇧Tab` | The next or previous window, round and round. |
| `⌥⇧←`, `⌥⇧→` | Move the front window one place earlier or later in the stack. |

On a tall display, where tiles go above each other, use `⌥↑` and `⌥↓` instead of left and right.

At the first or last window, the arrows stop. Turn on Settings > Layout > Focus and move past the edge to have them go on into the next workspace.

## The stack strip

When you go to a stack, or another of its windows comes to the front, a strip shows at the top of the stack. It lists the windows in order with each app's icon and the window's title, highlights the front one, and says where it sits, like "2 of 4".

![The stack strip at the top of a stack](images/stack-strip-dark.png)

The strip shows for 0.7 seconds and then fades. It floats over the windows and never takes space from them. When the titles don't fit, it shows the front window's title alone. It appears only for stacks of two windows or more.

## Peek edges

Peek edges, in Settings > Layout > Stacks, move the windows behind the front one aside by up to 16 points, so you can see they're there. The window before the front one shows its left edge and the one after it shows its right edge, like the padding in AeroSpace's accordion.

It's off by default. In the config file it's `layout:stack_peek`, a number of points from 0 to 16.
