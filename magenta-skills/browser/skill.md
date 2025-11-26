---
name: browser
description: Automate browser actions using Puppeteer with a simple DSL for web testing and automation
---

# Browser Automation Skill

This skill provides browser automation using Puppeteer through a simple DSL. You can use it to:
- Test web applications
- Scrape web content
- Automate repetitive browser tasks
- Take screenshots of pages

## Installation

First, install dependencies in the skill directory:

```bash
cd ~/.magenta/skills/browser
pnpm install --frozen-lockfile
```

This will install Puppeteer, TypeScript, and tsx using the exact versions from the lockfile.

## Usage

### Running from Command Line

```bash
cd ~/.magenta/skills/browser && npx tsx scripts/browser.ts "
load('https://www.google.com')
waitForElement('textarea[name=q]')
click('textarea[name=q]')
type('hello world')
sleep(500)
waitForElement('input[value=\"Google Search\"]')
click('input[value=\"Google Search\"]')
waitForNewPage('google.com/search')
screenshot('result.png')
"
```

## Available Commands

- `load(url)` - Navigate to a URL
  - `url`: URL string
- `waitForElement(selector)` - Wait for an element to appear (30s timeout)
  - `selector`: CSS selector
- `click(selector)` - Click an element
  - `selector`: CSS selector
- `type(text)` - Type text into the currently focused element
  - `text`: Text string
- `waitForNewPage(urlPattern)` - Wait for navigation to a URL containing the pattern
  - `urlPattern`: URL pattern
- `screenshot(filename)` - Take a screenshot and save to `/tmp/magenta/`
  - `filename`: File path
- `sleep(ms)` - Wait for a specified duration
  - `ms`: Milliseconds
- `hover(selector)` - Hover over an element
  - `selector`: CSS selector
- `select(selector, value)` - Select an option from a dropdown
  - `selector`: CSS selector
  - `value`: Value to select
- `focus(selector)` - Focus an element
  - `selector`: CSS selector
- `pressKey(key)` - Press a keyboard key (e.g., 'Enter', 'Escape', 'Tab')
  - `key`: Key name
- `getText(selector)` - Get and log the text content of an element
  - `selector`: CSS selector
- `getAttribute(selector, attr)` - Get and log an element's attribute value
  - `selector`: CSS selector
  - `attr`: Attribute name
- `reload()` - Reload the current page
- `saveContent(filename)` - Save page HTML to `/tmp/magenta/`
  - `filename`: File path
- `keepOpen()` - Keep browser open after script completes (useful for debugging)

## DSL Syntax

- One command per line
- Commands use the format: `commandName(arg1, arg2, ...)`
- Arguments can be quoted with single or double quotes
- Lines starting with `#` are treated as comments
- Empty lines are ignored
