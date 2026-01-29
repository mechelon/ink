import AppKit
import Darwin
@preconcurrency import WebKit
import Down

private let usage = """
Usage: ink [--icon <path>] [--no-detach] <path-to-markdown>

Options:
  -i, --icon <path>   Path to a PNG/ICNS to use as the Dock icon.
  --no-detach         Keep the CLI process attached to the window.
  -h, --help          Show help.

Environment:
  INK_ICON            Icon path (used if --icon is not provided).
"""

private func printError(_ message: String) {
    if let data = (message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func resolveFileURL(from argument: String) -> URL {
    let expanded = (argument as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: cwd)).standardizedFileURL
}

private func resolveOptionalFileURL(from argument: String?) -> URL? {
    guard let argument, !argument.isEmpty else { return nil }
    return resolveFileURL(from: argument)
}

private func loadBundledIcon() -> NSImage? {
    let extensions = ["icns", "png", "jpg", "jpeg"]
    for ext in extensions {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: ext),
           let image = NSImage(contentsOf: url) {
            return insetIconImage(image, scale: 0.94)
        }
    }
    return nil
}

private func insetIconImage(_ image: NSImage, scale: CGFloat) -> NSImage {
    let size = image.size
    let output = NSImage(size: size)
    output.lockFocus()
    defer { output.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let insetX = (1.0 - scale) * size.width / 2.0
    let insetY = (1.0 - scale) * size.height / 2.0
    let targetRect = NSRect(
        x: insetX,
        y: insetY,
        width: size.width * scale,
        height: size.height * scale
    )
    image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    output.isTemplate = image.isTemplate
    return output
}

private func makeDefaultIcon() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let backgroundRect = NSRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48)
    let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 100, yRadius: 100)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.88, alpha: 1.0),
        NSColor(calibratedRed: 0.92, green: 0.86, blue: 0.78, alpha: 1.0)
    ])
    gradient?.draw(in: backgroundPath, angle: -90)

    NSColor(calibratedWhite: 0.1, alpha: 0.08).setStroke()
    backgroundPath.lineWidth = 6
    backgroundPath.stroke()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = NSSize(width: 0, height: -4)
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.2)

    let text = "ink"
    let font = NSFont.systemFont(ofSize: 180, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.1, alpha: 1.0),
        .shadow: shadow
    ]
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (size.width - textSize.width) / 2.0,
        y: (size.height - textSize.height) / 2.0 - 8.0,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    let dotSize: CGFloat = 64
    let dotRect = NSRect(
        x: backgroundRect.maxX - dotSize - 36,
        y: backgroundRect.maxY - dotSize - 36,
        width: dotSize,
        height: dotSize
    )
    NSColor(calibratedRed: 0.1, green: 0.09, blue: 0.08, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    image.isTemplate = false
    return image
}

private func loadIconImage(from url: URL) -> NSImage? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        return nil
    }
    return NSImage(contentsOf: url)
}

private enum ParsedInput {
    case run(fileURL: URL, iconURL: URL?, detach: Bool)
    case exit(code: Int)
}

private func parseArguments() -> ParsedInput {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty {
        print(usage)
        return .exit(code: 1)
    }

    var filePath: String?
    var iconPath: String?
    var detach = true
    var isDetached = false
    var index = 0

    while index < args.count {
        let arg = args[index]
        if arg == "-h" || arg == "--help" {
            print(usage)
            return .exit(code: 0)
        } else if arg == "-i" || arg == "--icon" {
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                printError("Missing value for --icon")
                print(usage)
                return .exit(code: 1)
            }
            iconPath = args[nextIndex]
            index = nextIndex + 1
            continue
        } else if arg.hasPrefix("--icon=") {
            iconPath = String(arg.dropFirst("--icon=".count))
            index += 1
            continue
        } else if arg == "--no-detach" {
            detach = false
        } else if arg == "--detached" {
            isDetached = true
        } else if arg == "--" {
            let nextIndex = index + 1
            guard nextIndex < args.count else {
                printError("Missing markdown file path")
                print(usage)
                return .exit(code: 1)
            }
            filePath = args[nextIndex]
            index = args.count
            continue
        } else if arg.hasPrefix("-") {
            printError("Unknown option: \(arg)")
            print(usage)
            return .exit(code: 1)
        } else if filePath == nil {
            filePath = arg
        } else {
            printError("Unexpected argument: \(arg)")
            print(usage)
            return .exit(code: 1)
        }
        index += 1
    }

    guard let filePath else {
        print(usage)
        return .exit(code: 1)
    }

    let fileURL = resolveFileURL(from: filePath)
    let iconCandidate = iconPath ?? ProcessInfo.processInfo.environment["INK_ICON"]
    let iconURL = resolveOptionalFileURL(from: iconCandidate)
    let shouldDetach = detach && !isDetached
    return .run(fileURL: fileURL, iconURL: iconURL, detach: shouldDetach)
}

private func htmlEscaped(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private enum ColumnAlignment {
    case left, center, right
}

private func parseTableRow(_ line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("|") else { return nil }

    var cells: [String] = []
    var current = ""
    var inCell = false

    for char in trimmed {
        if char == "|" {
            if inCell {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            inCell = true
        } else {
            current.append(char)
        }
    }

    return cells.isEmpty ? nil : cells
}

private func parseSeparatorRow(_ line: String) -> [ColumnAlignment]? {
    guard let cells = parseTableRow(line) else { return nil }
    var alignments: [ColumnAlignment] = []

    for cell in cells {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }

        let hasLeftColon = trimmed.hasPrefix(":")
        let hasRightColon = trimmed.hasSuffix(":")

        if hasLeftColon && hasRightColon {
            alignments.append(.center)
        } else if hasRightColon {
            alignments.append(.right)
        } else {
            alignments.append(.left)
        }
    }

    return alignments.isEmpty ? nil : alignments
}

private func tableRowToHTML(_ cells: [String], alignments: [ColumnAlignment], isHeader: Bool) -> String {
    let tag = isHeader ? "th" : "td"
    var html = "<tr>"

    for (index, cell) in cells.enumerated() {
        let alignment = index < alignments.count ? alignments[index] : .left
        let style: String
        switch alignment {
        case .left:
            style = ""
        case .center:
            style = " style=\"text-align: center;\""
        case .right:
            style = " style=\"text-align: right;\""
        }
        html += "<\(tag)\(style)>\(htmlEscaped(cell))</\(tag)>"
    }

    html += "</tr>"
    return html
}

private func preprocessMarkdownTables(_ markdown: String) -> String {
    let lines = markdown.components(separatedBy: "\n")
    var result: [String] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Check if this could be a table header row
        if let headerCells = parseTableRow(line), i + 1 < lines.count {
            let nextLine = lines[i + 1]
            if let alignments = parseSeparatorRow(nextLine) {
                // Found a table
                var tableHTML = "<table>\n<thead>\n"
                tableHTML += tableRowToHTML(headerCells, alignments: alignments, isHeader: true)
                tableHTML += "\n</thead>\n<tbody>\n"

                i += 2

                while i < lines.count {
                    if let rowCells = parseTableRow(lines[i]) {
                        tableHTML += tableRowToHTML(rowCells, alignments: alignments, isHeader: false)
                        tableHTML += "\n"
                        i += 1
                    } else {
                        break
                    }
                }

                tableHTML += "</tbody>\n</table>"
                result.append(tableHTML)
                continue
            }
        }

        result.append(line)
        i += 1
    }

    return result.joined(separator: "\n")
}

private let baseCSS = #"""
:root {
  color-scheme: light dark;
}

body {
  margin: 0;
  padding: 48px 56px 64px;
  font-family: "Iowan Old Style", "Palatino", "Palatino Linotype", "Times New Roman", serif;
  font-size: 17px;
  line-height: 1.65;
  background: #fdfbf7;
  color: #1c1b1a;
}

main {
  max-width: 920px;
  margin: 0 auto;
}

h1, h2, h3, h4, h5, h6 {
  font-family: "Palatino", "Iowan Old Style", "Times New Roman", serif;
  line-height: 1.2;
  margin: 1.8em 0 0.6em;
}

h1 {
  font-size: 2.4rem;
  letter-spacing: -0.01em;
}

h2 {
  font-size: 1.9rem;
}

h3 {
  font-size: 1.5rem;
}

p {
  margin: 0.9em 0;
}

a {
  color: #0f5cc9;
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

blockquote {
  margin: 1.5em 0;
  padding: 0.3em 1.2em;
  border-left: 3px solid #d5c9b6;
  color: #4e4a44;
  background: rgba(213, 201, 182, 0.2);
}

ul, ol {
  padding-left: 1.4em;
  margin: 1em 0;
}

li {
  margin: 0.35em 0;
}

code {
  font-family: "SF Mono", "Menlo", "Monaco", "Consolas", monospace;
  font-size: 0.92em;
  background: rgba(15, 92, 201, 0.08);
  padding: 0.1em 0.3em;
  border-radius: 4px;
}

pre {
  position: relative;
  background: #f3efe8;
  padding: 18px 20px;
  border-radius: 10px;
  overflow-x: auto;
  margin: 1.2em 0;
}

pre code {
  background: none;
  padding: 0;
  font-size: 0.9em;
  display: block;
  white-space: pre;
}

.copy-button {
  position: absolute;
  top: 12px;
  right: 12px;
  font-size: 12px;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  border: 1px solid rgba(28, 27, 26, 0.25);
  background: rgba(253, 251, 247, 0.9);
  color: #1c1b1a;
  padding: 4px 8px;
  border-radius: 6px;
  cursor: pointer;
}

.copy-button.copied {
  border-color: rgba(7, 115, 65, 0.5);
  color: #077341;
}

table {
  border-collapse: collapse;
  width: 100%;
  margin: 1.4em 0;
  font-size: 0.95em;
}

th, td {
  border: 1px solid #dbcfc0;
  padding: 10px 12px;
  text-align: left;
}

th {
  background: #f3ede3;
}

img {
  max-width: 100%;
  border-radius: 10px;
  margin: 1em 0;
}

.token.keyword {
  color: #8b2d64;
  font-weight: 600;
}

.token.string {
  color: #0e6b3a;
}

.token.comment {
  color: #6f6a64;
  font-style: italic;
}

.token.number {
  color: #1a5fb4;
}

@media (prefers-color-scheme: dark) {
  body {
    background: #0f1113;
    color: #ece7e1;
  }

  a {
    color: #9ad1ff;
  }

  blockquote {
    border-left-color: #4b4a44;
    background: rgba(255, 255, 255, 0.05);
    color: #c4c0bb;
  }

  code {
    background: rgba(154, 209, 255, 0.12);
  }

  pre {
    background: #1c1f22;
  }

  .copy-button {
    border-color: rgba(236, 231, 225, 0.2);
    background: rgba(15, 17, 19, 0.9);
    color: #ece7e1;
  }

  .copy-button.copied {
    border-color: rgba(106, 227, 156, 0.5);
    color: #6ae39c;
  }

  th, td {
    border-color: #2b2f33;
  }

  th {
    background: #191c20;
  }

  .token.keyword {
    color: #f08db0;
  }

  .token.string {
    color: #7fe19d;
  }

  .token.comment {
    color: #8a9096;
  }

  .token.number {
    color: #7fb6ff;
  }
}
"""#

private let highlightScript = #"""
(() => {
  const aliases = {
    js: "javascript",
    javascript: "javascript",
    ts: "javascript",
    typescript: "javascript",
    py: "python",
    python: "python",
    sh: "bash",
    bash: "bash",
    zsh: "bash",
    swift: "swift",
    json: "json"
  };

  const keywordSets = {
    swift: [
      "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
      "import", "return", "if", "else", "switch", "case", "for", "while", "in",
      "guard", "defer", "do", "catch", "try", "throws", "throw", "public", "private",
      "fileprivate", "internal", "open", "static", "final", "override", "where"
    ],
    javascript: [
      "const", "let", "var", "function", "class", "return", "if", "else", "switch",
      "case", "for", "while", "in", "of", "try", "catch", "finally", "throw", "new",
      "this", "super", "import", "export", "default", "async", "await"
    ],
    python: [
      "def", "class", "return", "if", "elif", "else", "for", "while", "in", "try",
      "except", "finally", "import", "from", "as", "pass", "break", "continue",
      "with", "lambda", "yield", "True", "False", "None"
    ],
    bash: [
      "if", "then", "fi", "for", "while", "do", "done", "function", "case",
      "esac", "in", "select", "elif", "else"
    ],
    json: ["true", "false", "null"]
  };

  const stringPatterns = {
    swift: /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
    javascript: /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`/g,
    python: /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
    bash: /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
    json: /"(?:\\.|[^"\\])*"/g
  };

  const commentPatterns = {
    swift: /\/\/[^\n]*|\/\*[\s\S]*?\*\//g,
    javascript: /\/\/[^\n]*|\/\*[\s\S]*?\*\//g,
    python: /#[^\n]*/g,
    bash: /#[^\n]*/g,
    json: null
  };

  function normalizeLang(lang) {
    if (!lang) return "plain";
    const lower = lang.toLowerCase();
    return aliases[lower] || lower;
  }

  function escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function wrapToken(text, klass) {
    return `<span class="token ${klass}">${escapeHtml(text)}</span>`;
  }

  function buildTokenRegex(lang) {
    const stringPattern = stringPatterns[lang];
    const commentPattern = commentPatterns[lang];
    if (!stringPattern && !commentPattern) {
      return null;
    }
    const parts = [];
    if (stringPattern) parts.push(stringPattern.source);
    if (commentPattern) parts.push(commentPattern.source);
    return new RegExp(parts.join("|"), "g");
  }

  function highlightPlain(text, lang) {
    const keywords = keywordSets[lang] || [];
    const keywordPattern = keywords.length
      ? new RegExp(`\\b(${keywords.join("|")})\\b|\\b\\d+(?:\\.\\d+)?\\b`, "g")
      : /\b\d+(?:\.\d+)?\b/g;

    let result = "";
    let lastIndex = 0;
    let match;

    while ((match = keywordPattern.exec(text)) !== null) {
      const token = match[0];
      result += escapeHtml(text.slice(lastIndex, match.index));
      const klass = /^\d/.test(token) ? "number" : "keyword";
      result += wrapToken(token, klass);
      lastIndex = match.index + token.length;
    }

    result += escapeHtml(text.slice(lastIndex));
    return result;
  }

  function highlightCode(code, lang) {
    const tokenRegex = buildTokenRegex(lang);
    if (!tokenRegex) {
      return highlightPlain(code, lang);
    }

    let result = "";
    let lastIndex = 0;
    let match;

    while ((match = tokenRegex.exec(code)) !== null) {
      const token = match[0];
      result += highlightPlain(code.slice(lastIndex, match.index), lang);
      const klass = token.startsWith("/") || token.startsWith("#") ? "comment" : "string";
      result += wrapToken(token, klass);
      lastIndex = match.index + token.length;
    }

    result += highlightPlain(code.slice(lastIndex), lang);
    return result;
  }

  function addCopyButton(pre) {
    if (pre.querySelector(".copy-button")) return;
    const button = document.createElement("button");
    button.className = "copy-button";
    button.type = "button";
    button.textContent = "Copy";
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      copyPre(pre, button);
    });
    pre.appendChild(button);
  }

  function copyPre(pre, button) {
    const selection = window.getSelection();
    if (selection && selection.toString().length > 0) return;
    const text = pre.innerText || "";

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        if (button) flashCopied(button);
      }).catch(() => {
        legacyCopy(text, button);
      });
    } else {
      legacyCopy(text, button);
    }
  }

  function legacyCopy(text, button) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    try {
      document.execCommand("copy");
      if (button) flashCopied(button);
    } finally {
      document.body.removeChild(textarea);
    }
  }

  function flashCopied(button) {
    button.classList.add("copied");
    button.textContent = "Copied";
    setTimeout(() => {
      button.classList.remove("copied");
      button.textContent = "Copy";
    }, 1400);
  }

  function enhanceCodeBlocks() {
    document.querySelectorAll("pre code").forEach((code) => {
      const className = code.className || "";
      const match = className.match(/language-([a-zA-Z0-9_-]+)/);
      const language = normalizeLang(match ? match[1] : "plain");
      const raw = code.textContent || "";
      const highlighted = highlightCode(raw, language);
      code.innerHTML = highlighted;
      const pre = code.parentElement;
      if (!pre) return;
      addCopyButton(pre);
      pre.addEventListener("click", () => copyPre(pre, pre.querySelector(".copy-button")));
    });
  }

  document.addEventListener("DOMContentLoaded", enhanceCodeBlocks);
})();
"""#

private func makeHTML(bodyHTML: String, title: String) -> String {
    let escapedTitle = htmlEscaped(title)
    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>\(escapedTitle)</title>
      <style>\(baseCSS)</style>
    </head>
    <body>
      <main>\(bodyHTML)</main>
      <script>\(highlightScript)</script>
    </body>
    </html>
    """
}

private func makeErrorHTML(message: String) -> String {
    let body = "<h1>Unable to load file</h1><p>\(htmlEscaped(message))</p>"
    return makeHTML(bodyHTML: body, title: "ink")
}

final class InkApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let fileURL: URL
    private var window: NSWindow?
    private var webView: WKWebView?
    private var fileDescriptor: CInt = -1
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.contentView = webView
        window.setFrameAutosaveName("InkMainWindow")
        if !window.setFrameUsingName("InkMainWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.webView = webView

        reload(nil)
        startFileWatcher()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopFileWatcher()
    }

    @objc func reload(_ sender: Any?) {
        guard let webView else { return }
        do {
            let markdown = try String(contentsOf: fileURL, encoding: .utf8)
            let processedMarkdown = preprocessMarkdownTables(markdown)
            let htmlBody = try Down(markdownString: processedMarkdown).toHTML([.smart, .unsafe])
            let html = makeHTML(bodyHTML: htmlBody, title: fileURL.lastPathComponent)
            webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
        } catch {
            let html = makeErrorHTML(message: error.localizedDescription)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reload(nil)
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func startFileWatcher() {
        stopFileWatcher()
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        fileWatcher = source
        source.resume()
    }

    private func stopFileWatcher() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func handleFileEvent() {
        guard let watcher = fileWatcher else { return }
        let flags = watcher.data
        if flags.contains(.rename) || flags.contains(.delete) {
            startFileWatcher()
        }
        scheduleReload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if url.isFileURL {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

private func buildMainMenu(appName: String, target: InkApp) {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "File")
    let reloadItem = NSMenuItem(title: "Reload", action: #selector(InkApp.reload(_:)), keyEquivalent: "r")
    reloadItem.target = target
    fileMenu.addItem(reloadItem)
    fileMenuItem.submenu = fileMenu

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowMenu.addItem(.separator())
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowMenuItem.submenu = windowMenu

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
}

private let parsedInput = parseArguments()
let fileURL: URL
let iconURL: URL?
let shouldDetach: Bool

switch parsedInput {
case .exit(let code):
    exit(Int32(code))
case .run(let resolvedFileURL, let resolvedIconURL, let detach):
    fileURL = resolvedFileURL
    iconURL = resolvedIconURL
    shouldDetach = detach
}

var isDirectory: ObjCBool = false
if !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) || isDirectory.boolValue {
    printError("File not found: \(fileURL.path)")
    exit(1)
}

private func resolveExecutableURL() -> URL? {
    let arg0 = CommandLine.arguments.first ?? "ink"
    if arg0.contains("/") {
        return URL(fileURLWithPath: arg0).standardizedFileURL
    }

    let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let searchPaths = pathEnv.split(separator: ":").map(String.init)
    let fileManager = FileManager.default

    for path in searchPaths {
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(arg0)
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }

    return nil
}

private func launchDetached(fileURL: URL, iconURL: URL?) -> Bool {
    guard let executableURL = resolveExecutableURL() else {
        return false
    }

    let process = Process()
    process.executableURL = executableURL
    var arguments = ["--detached"]
    if let iconURL {
        arguments.append(contentsOf: ["--icon", iconURL.path])
    }
    arguments.append(fileURL.path)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let nullHandle = FileHandle.nullDevice
    process.standardInput = nullHandle
    process.standardOutput = nullHandle
    process.standardError = nullHandle

    do {
        try process.run()
        return true
    } catch {
        return false
    }
}

if shouldDetach {
    if launchDetached(fileURL: fileURL, iconURL: iconURL) {
        exit(0)
    } else {
        printError("Unable to launch detached window; running attached.")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.applicationIconImage = loadBundledIcon() ?? makeDefaultIcon()
if let iconURL {
    if let iconImage = loadIconImage(from: iconURL) {
        app.applicationIconImage = iconImage
    } else {
        printError("Unable to load icon: \(iconURL.path) (using default)")
    }
}

let delegate = InkApp(fileURL: fileURL)
app.delegate = delegate
buildMainMenu(appName: "ink", target: delegate)
app.run()
