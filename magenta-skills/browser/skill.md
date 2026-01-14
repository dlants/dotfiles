---
name: browser
description: Automate browser actions using Puppeteer with a simple DSL for web testing and automation
---

# Browser Automation Skill

This skill uses [pkgx](https://pkgx.sh) to run tools without global installation:

- **Node scripts**: `pkgx pnpm exec tsx script.ts`
- **Python scripts**: `pkgx uv run script.py`

This skill provides browser automation using Puppeteer through a simple DSL. You can use it to:

- Test web applications
- Scrape web content
- Automate repetitive browser tasks
- Take screenshots of pages

## Installation

First, install dependencies in the skill directory:

```bash
cd ~/.claude/skills/browser
pkgx pnpm install
```

This will install Puppeteer, TypeScript, and tsx.

Then install Chrome for Puppeteer:

```bash
npx puppeteer browsers install chrome
```

This downloads a compatible Chrome version to `~/.cache/puppeteer/`.

## Usage

### Running from Command Line

```bash
cd ~/.claude/skills/browser && pkgx pnpm exec tsx scripts/browser.ts "
load https://www.google.com
waitForElement textarea[name=q]
click textarea[name=q]
type hello world
sleep 500
waitForElement input[value=\"Google Search\"]
click input[value=\"Google Search\"]
waitForNewPage google.com/search
screenshot result.png
"
```

## Available Commands

- `load <url>` - Navigate to a URL
- `waitForElement <selector>` - Wait for an element to appear (30s timeout)
- `click <selector>` - Click an element
- `type <text>` - Type text into the currently focused element
- `waitForNewPage <urlPattern>` - Wait for navigation to a new page, then verify the URL contains the given pattern (substring match)
- `screenshot <filename>` - Take a screenshot and save to `/tmp/magenta/`
- `sleep <ms>` - Wait for a specified duration in milliseconds
- `hover <selector>` - Hover over an element
- `select <selector> <value>` - Select an option from a dropdown
- `focus <selector>` - Focus an element
- `pressKey <key>` - Press a keyboard key (e.g., Enter, Escape, Tab)
- `getText <selector>` - Get and log the text content of an element
- `getAttribute <selector> <attribute>` - Get and log an element's attribute value
- `reload` - Reload the current page
- `saveContent <filename>` - Save page HTML to `/tmp/magenta/`
- `keepOpen` - Keep browser open after script completes (useful for debugging)
- `eval` / `endeval` - Execute JavaScript code in the page context
  ```
  eval
  console.log('Hello from page context');
  return document.title;
  endeval
  ```

## DSL Syntax

- One command per line (except `eval` blocks)
- Commands use the format: `commandName arg1 arg2 ...`
- No quotes or parentheses needed - arguments are separated by whitespace
- Multi-line code blocks supported with `eval` / `endeval`
- Lines starting with `#` are treated as comments
- Empty lines are ignored

### Examples

Simple commands:

```
load https://example.com
click button.submit
type Hello World
waitForNewPage example.com/results  # Waits for navigation, then checks URL contains "example.com/results"
```

Multi-line eval block:

```
eval
const title = document.querySelector('h1').textContent;
console.log('Title:', title);
return title;
endeval
```
