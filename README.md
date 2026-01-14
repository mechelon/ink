# ink

`ink` is a minimal, fast macOS Markdown viewer built in Swift. It opens a native window that renders Markdown with clean typography, syntax highlighting, and link handling.

<img width="2140" height="1552" alt="CleanShot 2026-01-14 at 11 00 10@2x" src="https://github.com/user-attachments/assets/0f363f4f-1097-4021-81f7-ab995e040934" />


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

## Features

- Full Markdown rendering (tables, blockquotes, links, images)
- Syntax highlighting for common languages
- Automatic light/dark mode
- Cmd+R to reload
- Cmd+Q / Cmd+W to quit/close
- Click links to open in your default browser
- Click a code block or its Copy button to copy
