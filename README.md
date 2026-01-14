# ink

`ink` is a minimal, fast macOS Markdown viewer built in Swift. It opens a native window that renders Markdown with clean typography, syntax highlighting, and link handling.

## Requirements

- macOS 13+
- Xcode or the Swift toolchain

## Build

```bash
swift build -c release
```

## Run

```bash
.build/release/ink README.md
```

## Install

```bash
./install.sh
```

If `/usr/local/bin` requires elevated permissions, run:

```bash
sudo ./install.sh
```

## Usage

```bash
ink /path/to/file.md
```

By default, `ink` exits immediately after launching the window. To keep the CLI attached, run:

```bash
ink --no-detach /path/to/file.md
```

## Custom Dock icon

To bake an icon into the binary, add a PNG or ICNS at:

`Sources/ink/Resources/AppIcon.png` (or `.icns`)

Then rebuild. The app will use it by default.

You can also override the Dock icon at runtime:

```bash
ink --icon /path/to/AppIcon.png README.md
```

Or set it via environment variable:

```bash
INK_ICON=/path/to/AppIcon.icns ink README.md
```

If no icon is provided, ink uses a built-in default.

## Features

- Full Markdown rendering (tables, blockquotes, links, images)
- Syntax highlighting for common languages
- Automatic light/dark mode
- Cmd+R to reload
- Cmd+Q / Cmd+W to quit/close
- Click links to open in your default browser
- Click a code block or its Copy button to copy
