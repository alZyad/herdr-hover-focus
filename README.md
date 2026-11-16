# herdr-hover-focus

Focus follows the mouse for [herdr](https://herdr.dev) panes running in Ghostty on macOS.
Rest the pointer on a pane for 200ms and it gets the keyboard.

## Install

```sh
make install
```

Builds `~/Applications/HerdrHoverFocus.app` and registers a LaunchAgent that starts it at login.

- `make log` follows `/tmp/herdr-hover-focus.log`
- `make uninstall` removes it
- `--delay <ms>` in `launchagent.plist` changes the dwell time

## How it works

A listen-only CGEvent tap receives mouse moves. When Ghostty is frontmost, the pointer is mapped to a terminal cell using the Ghostty window bounds, Ghostty's padding and the herdr client tty size (`TIOCGWINSZ`), then matched against herdr's `pane.layout` and focused with `pane.focus` over herdr's socket.

## Limits

- Ghostty only, one herdr client window, default herdr session
- Sidebar on the left, tab bar top or bottom
- Ignored while a pane is zoomed; herdr popups don't block it
