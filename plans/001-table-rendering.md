# Task: Markdown Table Rendering

## Context

`ink` is a minimal, fast macOS Markdown viewer built in Swift. It renders Markdown files in a native WebKit view with clean typography and syntax highlighting.

**Architecture:**
- Single file: `Sources/ink/main.swift` (~1000 lines)
- Uses the `Down` library to convert Markdown → HTML
- HTML is rendered in a `WKWebView` with custom CSS
- CSS already includes table styles (see `baseStyles` in main.swift)

## Problem

Markdown tables are not rendering properly. The CSS for tables exists:

```css
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
```

But the HTML table elements aren't being generated from Markdown table syntax.

## Expected Behavior

Standard Markdown tables like this:

```markdown
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
| Cell 3   | Cell 4   |
```

Should render as proper HTML tables with the existing styling applied.

## Investigation Steps

1. Check how `Down` is being called and what options are passed
2. Verify if `Down` supports GFM (GitHub Flavored Markdown) tables
3. If Down doesn't support tables, consider:
   - Using Down with different options
   - Pre-processing the markdown to convert tables
   - Switching to a different markdown parser that supports GFM

## Files to Check

- `Sources/ink/main.swift` – look for the `Down` usage and HTML generation
- `Package.swift` – current Down dependency version

## Acceptance Criteria

- [ ] Markdown tables render as HTML tables
- [ ] Existing table CSS styles are applied
- [ ] Works in both light and dark mode
- [ ] Column alignment syntax supported (`:---`, `:---:`, `---:`)
