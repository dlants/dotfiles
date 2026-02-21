# Denis Lantsman Neovim Config - Guide for Web Development

## 0. Installation

### Prerequisites
- macOS (Apple Silicon) or Linux (aarch64)
- Git installed
- About 10 minutes for first-time setup

### Automated Setup

These dotfiles use **Nix + Home Manager** for reproducible, automated configuration.

#### One-Time Installation

```bash
# Clone the repository
git clone https://github.com/dlants/dotfiles ~/src/dlants-dotfiles
cd ~/src/dlants-dotfiles

# grep dotfiles to personalize parametrized directory names & home path

# Run automated setup
./setup.sh
```

**What `setup.sh` does:**
1. Detects your platform (macOS → darwin profile, Linux → devcontainer)
2. Installs Nix package manager (if not already installed)
3. Enables Nix flakes support
4. Runs Home Manager to install and configure everything

**What gets installed automatically:**
- ✅ Neovim 0.10+ with full plugin suite (via Lazy.nvim)
- ✅ All language servers (TypeScript, Lua, Bash, YAML, ESLint)
- ✅ Code formatters (Prettier, Stylua)
- ✅ Fish shell with vi bindings
- ✅ Tmux with remote development support
- ✅ Development tools (ripgrep, fd, fzf, delta, gh, tree-sitter)
- ✅ Custom scripts (tmux session manager, clipboard sync)
- ✅ **macOS only**: nodejs, uv, Hammerspoon, Ghostty
- ✅ **Linux only**: pkgx, devcontainer utilities

**Live configuration:**
All configs are symlinked from the dotfiles repo, so you can edit them in place:
- `~/src/dlants-dotfiles/nvim/` → `~/.config/nvim/`
- `~/src/dlants-dotfiles/fish/` → `~/.config/fish/`
- `~/src/dlants-dotfiles/tmux.conf` → `~/tmux.conf`

#### First Launch



After setup completes:
```bash
# Verify Nix installation
nix-shell -p nix-info --run "nix-info -m"

# Start Neovim - plugins auto-install on first run
nvim

# Wait for Lazy.nvim to install all plugins (~30 seconds)
# When complete, restart Neovim
```

#### Platform-Specific Notes

**macOS (darwin profile):**
- Uses Homebrew for GUI apps (Hammerspoon, pkgx)
- Includes macOS-specific clipboard integration
- Fish config: `fish/config-darwin.fish`

**Linux (devcontainer profile):**
- Optimized for Docker/remote development
- Includes OSC52 clipboard sync for SSH
- Fish config: `fish/config-linux.fish`

---

## 1. Overview & Philosophy

This is a sophisticated Neovim configuration optimized for **TypeScript/JavaScript web development** with a focus on:

- **Speed**: Lightning-fast fuzzy finding, lazy-loaded plugins, smooth scrolling
- **Intelligence**: LSP-first development with excellent TypeScript support
- **AI-Augmented**: Claude integration for understanding complex code and assistance
- **Remote-First**: Custom clipboard handling that works through SSH/Docker
- **Discoverability**: Consistent keybinding patterns (unimpaired-style navigation)
- **Minimal UI**: Clean interface with on-demand information display

**Key Features:**
- Leader key: `<Space>` (mnemonic, easy to reach)
- Smooth scrolling and leap motion for rapid navigation
- Smart diagnostic display (shows on-demand, not cluttering)
- AI assistant (magenta.nvim) with Claude Opus 4.6
- Optimized for remote development workflows

---

## 2. Quick Start Checklist

### ✓ Installation Complete

If you've run `./setup.sh` from [Section 0](#0-installation), you already have:
- [x] Neovim 0.10+
- [x] Node.js (macOS: installed via Nix; Linux: use project's node via pkgx/nvm)
- [x] Git configured
- [x] TypeScript language servers (ts_ls, ESLint)
- [x] Supporting language servers (YAML, Bash, Lua)
- [x] Code formatters (Prettier, Stylua)

### ✓ Verify Setup

Open a TypeScript file to test your setup:

```bash
# Create a test project
mkdir -p ~/test-project
cd ~/test-project
npm init -y
echo 'export const greeting = "Hello";' > index.ts

# Open in Neovim
nvim index.ts
```

**Inside Neovim:**
1. Run `:LspInfo` - Should see `ts_ls: client id 1 (attached)`
2. Place cursor on `greeting` and press `gd` - Should navigate to declaration
3. Press `<leader>k` on `greeting` - Should show TypeScript type information

**If LSP isn't working:**
- **First launch?** Wait for Lazy.nvim to finish installing plugins (~30 seconds), then restart Neovim
- **Still not working?** See [Section 17: Troubleshooting](#17-troubleshooting-guide)

### ✓ Your First Week: Essential 10 Keybindings

Learn these first - they'll make you productive immediately:

| Key | Action | Try It On |
|-----|--------|-----------|
| `<leader>f` | Find files | Finding a component by name |
| `<leader>/` | Search in codebase | Finding where "useState" is used |
| `gd` | Go to definition | Jump from import to source file |
| `gr` | Find references | See all places a function is called |
| `<leader>k` | Show documentation | View TypeScript types |
| `<leader>r` | Rename symbol | Rename a variable everywhere |
| `<leader>` ` | Format code | Run prettier on file |
| `[d` / `]d` | Jump through errors | Navigate TypeScript errors |
| `s<2chars>` | Leap to location | Jump anywhere on screen |
| `-` | File explorer | Browse project structure |

**Practice routine:** Try each keybinding 3-5 times in your codebase today.

---

## 3. What Makes This Config Special

### Fast Fuzzy Finding
- **fff.nvim**: Blazing fast file finder (respects .gitignore)
- **fzf-lua**: Live grep with preview, buffer switching
- Navigate without leaving the keyboard

### Excellent TypeScript Support
- Full LSP integration (autocomplete, go-to-definition, refactoring)
- ESLint integration with auto-fix
- Prettier formatting
- Type-aware navigation

### Smart Diagnostics
- Errors/warnings inline as you type
- Virtual diagnostic lines **auto-hide** to reduce clutter
- Show on-demand when jumping through errors (`[d`/`]d`)
- Toggle temporarily with `<leader>e`

### AI Integration (magenta.nvim)
- Claude Opus 4.6 for code assistance
- Ask questions about unfamiliar code
- Get explanations for complex patterns
- Optional workflow enhancement (not required for daily use)

### Remote Development Ready
- Custom clipboard using OSC52 (works through tmux+ssh)
- Optimized for Docker development environments
- Shared clipboard file for paste operations

### Smooth Developer Experience
- 50ms smooth scrolling (neoscroll.nvim)
- Leap motion for instant jumps (`s` + 2 characters)
- Unimpaired-style navigation (`[` and `]` prefixes)
- Markdown-aware editing (visual line navigation)

### What This Repository Includes

This guide focuses on **Neovim configuration and usage**, but these dotfiles provide a complete development environment:

| Component | What It Provides |
|-----------|-----------------|
| **Neovim** | Full IDE-like experience with LSP, fuzzy finding, AI integration |
| **Fish Shell** | Vi key bindings, git helpers, custom functions |
| **Tmux** | Session management, remote development, vim integration |
| **Scripts** | `ta` (smart tmux sessions), clipboard sync, fzf helpers |
| **Hammerspoon** (macOS) | Window management automation |
| **Ghostty** (macOS) | Terminal emulator configuration |

All components work together seamlessly - for example:
- Tmux + Neovim share navigation keys (`<C-h/j/k/l>`)
- Fish shell title updates tmux pane names
- Clipboard sync works across SSH/Docker boundaries
- Remote sessions managed via `ta dev:/path/to/project`

See [Section 20: Beyond Neovim](#20-beyond-neovim-other-dotfiles-components) for details on these components.

---

## 4. Finding & Opening Code

### 4.1 Find a File by Name

**Quick start:** Press `<leader>f`, type part of filename, hit Enter.

#### FFF Finder Workflow

1. Press `<leader>f` (opens fff.nvim finder)
2. Start typing filename: `UserPro` → finds `UserProfile.tsx`
3. Navigate results with `<C-j>` / `<C-k>` (stay in input field!)
4. Press `<Enter>` to open file

**FFF Keybindings (while in finder):**
| Key | Action |
|-----|--------|
| `<C-j>` or `<Down>` | Move down in results |
| `<C-k>` or `<Up>` | Move up in results |
| `<Enter>` | Open selected file |
| `<Esc>` | Close finder |
| `<C-a>` | Jump to beginning of input |
| `<C-e>` | Jump to end of input |
| `<C-l>` or `<C-u>` | Clear search |

**Key insight:** You never leave the input field - just type → navigate → type more → navigate → open!

**Variants:**
- `<leader>f` - Files in git repo (respects .gitignore) ← **Use this 90% of the time**
- `<leader>F` - ALL files (including node_modules, .git) ← Use when looking in gitignored folders
- `<leader>p` - Search in ~/pkb (personal knowledge base)

### 4.2 Search for Text Across Codebase

**Live grep:** Press `<leader>/`, type search term, see results instantly.

**Workflow:**
1. `<leader>/` to open live grep
2. Type: `useState` (finds all occurrences)
3. Results show with preview
4. Navigate with `<C-j>` / `<C-k>`
5. Press `<Enter>` to jump to file

**Results go to quickfix list:**
- `:copen` to see quickfix window
- `]q` / `[q` to jump next/previous result
- `<Enter>` to open file at match

**Advanced search:**
- `<leader>g` - Open Grepper for regex/advanced options

### 4.3 Switch Between Files

#### Buffer List
`<leader>b` - Shows all open buffers with fuzzy search

**Use when:** You've had the file open recently, just need to switch back.

#### Smart Jump Between Files
`[J` / `]J` - Jump backward/forward in jump list **until buffer changes**

**Scenario:** You've been working in `UserProfile.tsx`, jumped to `types.ts` multiple times to check types. Press `[J` to jump directly back to `UserProfile.tsx`, skipping the intermediate jumps.

**Standard jump list:**
- `[j` / `]j` - Jump backward/forward (same as `<C-o>` / `<C-i>`)

### 4.4 Browse Project Structure

**Oil file explorer:** Press `-` to open current directory.

Oil lets you **edit the filesystem like a buffer**:
- Navigate with `j`/`k`
- Press `<Enter>` to open file/folder
- Edit filenames directly (like text editing)
- Save with `:w` to apply file operations
- LSP-aware: renaming updates imports!

**Use cases:**
- Browsing unfamiliar project structure
- Renaming files (updates imports automatically)
- Moving files around

---

## 5. Understanding Existing Code

### 5.1 Navigate to Definition

**Scenario:** You see `import { useAuth } from './hooks/useAuth'` and want to see the implementation.

**Workflow:**
1. Place cursor on `useAuth`
2. Press `gd`
3. Opens hook definition in current window

**Works for:**
- **Imports**: Jump from import statement to source file
- **Functions**: See function implementation
- **Types**: View type definition
- **React Components**: Navigate to component file
- **Variables**: Find where declared

**Jump back:**
- `<C-o>` - Jump back to where you were
- `<C-i>` - Jump forward again
- `[j` / `]j` - Same as above (unimpaired style)

**Related commands:**
| Key | Action | Use When |
|-----|--------|----------|
| `gd` | Go to definition | Jump to source/import |
| `gD` | Go to type definition | See the TypeScript type |
| `gi` | Go to implementation | Skip .d.ts, jump to actual code |

**Common issue:**
- ⚠️ `gd` opens `.d.ts` file in node_modules instead of source
  - This is expected for external libraries
  - Use `gi` (go to implementation) if available
  - Or just view the types and use `<C-o>` to go back

### 5.2 Find All Usages

**Scenario:** You want to see everywhere a function is called before refactoring it.

**Workflow:**
1. Place cursor on function name (e.g., `fetchUserData`)
2. Press `gr` (get references)
3. Results populate **quickfix list**
4. Type `:copen` to open quickfix window
5. Navigate with `]q` / `[q` (next/previous)
6. Press `<Enter>` to jump to reference
7. `<C-o>` to return, then `]q` for next reference

**Pro tip:** Use `:FzfLua lsp_references` for fuzzy search + live preview!

**Quickfix navigation:**
| Key | Action |
|-----|--------|
| `]q` / `[q` | Next/previous quickfix item |
| `]f` / `[f` | Next/previous quickfix list (if multiple searches) |
| `:copen` | Open quickfix window |
| `:cclose` | Close quickfix window |

### 5.3 View Documentation

**Quick docs:** Press `<leader>k` on any symbol.

**What you'll see:**
- TypeScript type signature
- JSDoc comments
- Function parameters and return types
- React prop types

**Workflow:**
1. Cursor on function/component/type
2. `<leader>k` - Floating window appears
3. Read documentation
4. Press `<leader>k` again to jump into window (if you need to scroll)
5. `q` or `<Esc>` to close

**Example:**
```typescript
// Cursor on useState
const [count, setCount] = useState(0);
// Press <leader>k → See full type signature and docs
```

### 5.4 Navigate Through Code Structure

**Jump by functions:**
- `]f` - Next function start
- `[f` - Previous function start
- `]F` - Next function end
- `[F` - Previous function end

**Jump by parameters:**
- `]a` - Next parameter/argument
- `[a` - Previous parameter/argument

**Use case:** Quickly scanning through a file to understand its structure.

**Select code blocks (Treesitter text objects):**
| Key | Selects |
|-----|---------|
| `vif` | Inside function (body only) |
| `vaf` | Around function (including declaration) |
| `vic` | Inside class |
| `vac` | Around class |
| `via` | Inside parameter |
| `vaa` | Around parameter |

**Example:**
```typescript
function calculateTotal(items: Item[]) {  // cursor here
  return items.reduce((sum, item) => sum + item.price, 0);
}
// Press daf → Delete entire function
// Press vif → Select just the function body
```

### 5.5 Understanding Complex Code

**Using AI (optional):**
- Select code with visual mode
- Ask: "What does this function do?"
- Get explanation of complex patterns, hooks, closures

**LSP-first approach:**
- Use `gd`, `gr`, `<leader>k` to understand most code
- Use AI when dealing with unfamiliar patterns or complex logic

---

## 6. Writing & Refactoring Code

### 6.1 LSP Autocomplete

**Just works as you type:**
- Type `use` → Suggests `useState`, `useEffect`, etc.
- Type `import` → Suggests modules
- Type `.` → Shows object methods/properties

**Navigate suggestions:**
| Key | Action |
|-----|--------|
| `<C-n>` | Next suggestion |
| `<C-p>` | Previous suggestion |
| `<Tab>` | Accept suggestion |
| `<C-y>` | Accept |
| `<C-e>` | Close completion menu |

**Autocomplete sources:**
- LSP (TypeScript/ESLint)
- Buffer words (from open files)
- File paths
- Neovim Lua API (when editing config)

### 6.2 Rename Symbols (TypeScript-Aware)

**Safe refactoring:** `<leader>r` renames everywhere across your project.

**Workflow:**
1. Cursor on variable/function/type name
2. Press `<leader>r`
3. Type new name
4. Press `<Enter>`
5. All references update automatically (including imports!)

**What gets renamed:**
- All usages in current file
- All usages across project files
- Import statements
- Export statements
- TypeScript type references

**Example:**
```typescript
// Before
export const userData = await fetchUser();
// Cursor on userData, press <leader>r, type "currentUser"

// After (automatically updates everywhere)
export const currentUser = await fetchUser();
```

### 6.3 Code Actions & Quick Fixes

**Auto-fix anything:** Press `<leader>x` for context-aware actions.

**Common actions offered:**
- **Missing imports**: Auto-import from correct module
- **ESLint fixes**: Apply lint suggestions
- **Type fixes**: Add missing type annotations
- **Extract to function**: Refactor selected code
- **Organize imports**: Sort and clean up imports
- **Implement interface**: Generate method stubs

**Workflow:**
1. Cursor on error/warning or highlighted code
2. Press `<leader>x`
3. FZF menu appears with available actions
4. Select action and press `<Enter>`

**Pro tip:** Works great with ESLint - automatically fixes common lint violations.

### 6.4 Format Code

**Prettier formatting:** Press `<leader>` ` (leader + backtick)

**What it does:**
- Runs prettier on current file
- Respects `.prettierrc` in project root
- Formats TypeScript, JavaScript, JSON, Markdown, CSS

**Create `.prettierrc` in your project:**
```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5"
}
```

**Auto-format on save:**
Not enabled by default (Denis's preference), but you can add to your config.

---

## 7. Fixing Errors & Debugging

### 7.1 View Diagnostics

**Diagnostics appear automatically as you type:**
- Inline error messages
- Virtual text showing issue
- Gutter signs (error/warning indicators)

**Smart display:**
- Virtual diagnostic lines are **hidden by default** (reduces clutter)
- Auto-show when jumping with `[d` or `]d`
- Manual toggle with `<leader>e`
- Auto-hide after cursor moves (50ms delay)

**Jump through errors:**
| Key | Action |
|-----|--------|
| `]d` | Next diagnostic (auto-shows details) |
| `[d` | Previous diagnostic (auto-shows details) |
| `<leader>e` | Temporarily show all diagnostic virtual lines |
| `<leader>d` | Show ALL diagnostics in quickfix list |

### 7.2 Understand an Error

**Read the diagnostic:**
1. Position cursor on error (red underline)
2. Error appears inline
3. Press `<leader>k` for hover info (sometimes provides more context)

**TypeScript errors are verbose:**
- Read carefully - they're usually accurate
- Check type signatures with `gD`
- Look at neighboring code for context

**For complex errors:**
- Copy error message
- Search online or ask AI: "Explain this TypeScript error..."

### 7.3 Quick Fix Workflow

**Many errors have auto-fixes:**

**Example - Missing Import:**
```typescript
// Error: Cannot find name 'useState'
const [count, setCount] = useState(0);
//                         ^^^^^^^^ red underline
```

1. Cursor on `useState`
2. Press `<leader>x` (code actions)
3. Select "Add import from 'react'"
4. Import auto-added at top!

**Example - ESLint Auto-fix:**
```typescript
// Warning: Missing semicolon
const name = "Denis"
//                  ^ warning
```

1. Cursor on line
2. Press `<leader>x`
3. Select "Fix: Add semicolon"

### 7.4 See All Errors in Project

**List everything:** Press `<leader>d`

**Workflow:**
1. `<leader>d` - Populates quickfix with all diagnostics
2. `:copen` - Opens quickfix window
3. See errors sorted by file
4. `]q` / `[q` to jump through
5. Fix high-priority errors first

**Filter by severity:**
- Quickfix shows both errors and warnings
- Errors are typically more critical
- Fix errors before warnings

---

## 8. Working with Git

### 8.1 View Changes in Current File

**Gutter signs:** Added/modified/deleted lines show automatically.

**Navigate hunks:**
| Key | Action |
|-----|--------|
| `]c` | Next git hunk (change) |
| `[c` | Previous git hunk |

**Perfect for code review:**
- See what changed since last commit
- Review your own work before committing
- Understand changes when doing `git pull`

### 8.2 Git Commands (vim-fugitive)

**Basic git workflow:**
```vim
:Git status          " See working tree status
:Git add %           " Stage current file
:Git commit          " Open commit message editor
:Git push            " Push to remote
:Git pull            " Pull from remote
```

**Useful commands:**
```vim
:Git blame           " See line-by-line authorship
:Git diff            " View changes
:Git log             " View commit history
:Git                 " Open interactive git status
```

**Fugitive's `:Git` command:**
- Opens git status in a buffer
- Press `-` to stage/unstage files
- Press `cc` to commit
- Press `ca` to amend
- Full vim editing for commit messages

### 8.3 Browse on GitHub

**Quick permalink to current file:**

| Command | Action |
|---------|--------|
| `:Gho` | Open current file on GitHub |
| `:Ghl` | Open with current line number |
| `:Ghom` | Open file on main branch |
| `:Ghlm` | Open main branch with line number |

**Use cases:**
- Sharing code location with teammates
- Viewing file history on GitHub
- Quick code review in browser
- Checking deployed version (main branch)

**Example:**
- You're on `feature/auth` branch at line 42 in `auth.ts`
- `:Ghl` opens browser to GitHub showing that exact line
- `:Ghlm` shows what line 42 looks like on main branch

---

## 9. Navigating Within Files

### 9.1 Instant Motion with Leap

**Fastest way to jump anywhere on screen:**

1. Press `s`
2. Type 2 characters of your target location
3. Jump labels appear
4. Press the label character to jump

**Example:**
```typescript
function getUserProfile() {
  const user = await fetchUser();
  const profile = await fetchProfile(user.id);
  return profile;
}
// Cursor at top, want to go to "profile" on line 3
// Press s + pr → Labels appear → Press label → Jump!
```

**Works in:**
- Normal mode (jump to location)
- Visual mode (select to location)
- Operator-pending mode (e.g., `d` then `s` + chars to delete to location)

**Bidirectional:**
- Searches both forward and backward
- Fastest for mid-range jumps (same screen)

### 9.2 Efficient Scrolling

**All scrolling is smooth (50-75ms animations):**

| Key | Action |
|-----|--------|
| `<C-d>` | Scroll down half page (50ms smooth) |
| `<C-u>` | Scroll up half page (50ms smooth) |
| `<C-f>` | Scroll down full page (75ms) |
| `<C-b>` | Scroll up full page (75ms) |
| `<C-e>` | Scroll down slightly (no cursor move, 25ms) |
| `<C-y>` | Scroll up slightly (no cursor move, 25ms) |

**Centering cursor:**
| Key | Action |
|-----|--------|
| `zz` | Center cursor on screen |
| `zt` | Position cursor at top |
| `zb` | Position cursor at bottom |

**Screen position movement:**
| Key | Action |
|-----|--------|
| `H` | Move cursor to top of screen |
| `M` | Move cursor to middle of screen |
| `L` | Move cursor to bottom of screen |

**Pro tip:**
- Use `<C-d>` / `<C-u>` for scanning code
- Use `zz` after jumps to center context
- Use `<C-e>` / `<C-y>` to peek above/below without moving cursor

### 9.3 Jump by Code Structure

**Paragraph/block motion:**
- `{` - Jump to previous blank line (paragraph up)
- `}` - Jump to next blank line (paragraph down)
- `%` - Jump to matching bracket/paren/brace

**Function motion (Treesitter-aware):**
- `]f` / `[f` - Next/previous function start
- `]F` / `[F` - Next/previous function end

**Use case: Scanning a file:**
1. Open large file
2. Press `}` repeatedly to scan through top-level blocks
3. When you see interesting function, press `<C-d>` to read it
4. Use `s` + chars to jump to specific line

### 9.4 Search Within File

**Forward/backward search:**
| Key | Action |
|-----|--------|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |
| `*` | Search word under cursor (forward) |
| `#` | Search word under cursor (backward) |
| `g*` | Partial word search |

**Character search (in-line):**
| Key | Action |
|-----|--------|
| `f<char>` | Find next character on line |
| `F<char>` | Find previous character on line |
| `t<char>` | Until next character (stop before) |
| `T<char>` | Jump to **last** occurrence in line (custom!) |
| `;` | Repeat last f/t/F/T |
| `,` | Reverse last f/t/F/T |

**Practical example:**
```typescript
const result = calculateTotal(items, tax, discount);
//    cursor here                                ^want to edit discount

// Fast way: Press f, then continue with fc → ; → ; to get to 'c' in 'discount'
// Or: Press sd to leap directly to 'discount'
```

---

## 10. Window Management

### 10.1 Navigate Between Splits

**Seamless split navigation:**

| Key | Action |
|-----|--------|
| `<C-h>` | Move to left split |
| `<C-j>` | Move to split below |
| `<C-k>` | Move to split above |
| `<C-l>` | Move to right split |

**Works with tmux:**
- vim-tmux-navigator plugin integrates with tmux
- Same keys work to move between vim splits AND tmux panes!

### 10.2 Resize Splits

| Key | Action |
|-----|--------|
| `<leader>=` | Increase window height (+5 lines) |
| `<leader>-` | Decrease window height (-5 lines) |

**Standard vim resize:**
- `<C-w>+` / `<C-w>-` - Increase/decrease height
- `<C-w>>` / `<C-w><` - Increase/decrease width
- `<C-w>=` - Make all windows equal size

### 10.3 Managing Splits

```vim
:split filename    " Horizontal split
:vsplit filename   " Vertical split
<C-w>s             " Split current window horizontally
<C-w>v             " Split current window vertically
<C-w>q             " Close current window
<C-w>o             " Close all windows except current
```

---

## 11. Language Server Configuration

### 11.1 What's Already Installed

If you used `./setup.sh`, all language servers are **automatically installed via Nix**:

| Language | Server | Package | Auto-Installed |
|----------|--------|---------|----------------|
| TypeScript/JavaScript | ts_ls | typescript-language-server | ✅ |
| ESLint | eslint | vscode-langservers-extracted | ✅ |
| JSON | jsonls | vscode-langservers-extracted | ✅ |
| YAML | yamlls | yaml-language-server | ✅ |
| Bash | bashls | bash-language-server | ✅ |
| Lua | lua_ls | lua-language-server | ✅ |

**Verify installation:**
```bash
# Check language servers are in PATH
which typescript-language-server
# Should show: /nix/store/.../bin/typescript-language-server

# Check in Neovim
nvim file.ts
:LspInfo
# Should show: ts_ls (client id 1) attached
```

### 11.2 How It Works

**Nix manages the language servers:**
- Defined in `nix/common.nix` (shared across platforms)
- Installed to Nix store (isolated, reproducible)
- Added to your PATH automatically
- No version conflicts with system packages

**Neovim discovers them automatically:**
- `nvim-lspconfig` plugin configures each server
- `lua/plugins/plugins.lua` contains LSP setup (around lines 550-750)
- Servers auto-attach when you open matching file types

**What each server provides:**

**TypeScript/JavaScript (ts_ls):**
- Type checking and IntelliSense
- Autocomplete for variables, functions, imports
- Go to definition, find references
- Rename refactoring
- React props support

**ESLint:**
- Linting errors and warnings
- Code style enforcement
- Auto-fix suggestions via `<leader>x`

**YAML, Bash, Lua:**
- Syntax validation
- Schema support (YAML)
- Contextual autocomplete

### 11.3 Adding New Language Servers

Want to add a language server not in the defaults?

**Option 1: Via Nix (Recommended)**
```bash
# 1. Edit the Nix configuration
nvim ~/src/dlants-dotfiles/nix/common.nix

# 2. Add package to home.packages (search nixpkgs for available servers)
# Example: pkgs.rust-analyzer

# 3. Rebuild Home Manager
cd ~/src/dlants-dotfiles
home-manager switch --flake .#macos  # or .#devcontainer
```

**Option 2: Via npm/cargo/pip**
```bash
# Install the language server binary directly
npm install -g some-language-server

# Add LSP configuration in lua/plugins/plugins.lua
# Then restart Neovim
```

### 11.4 Project-Specific Configuration

Language servers respect project config files - **no Neovim config changes needed**:

#### TypeScript (tsconfig.json)

Ensure your project has a `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "jsx": "react-jsx",
    "strict": true,
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

**LSP uses tsconfig.json to:**
- Understand module resolution
- Enforce type strictness
- Configure JSX handling

#### ESLint (.eslintrc.json)

Example configuration:

```json
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended"
  ],
  "parser": "@typescript-eslint/parser",
  "plugins": ["@typescript-eslint"],
  "rules": {
    "semi": ["error", "always"],
    "quotes": ["error", "single"]
  }
}
```

#### Prettier (.prettierrc)

```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "printWidth": 80
}
```

**LSP reads these automatically** when you open files in your project.

---

## 12. Complete Keybinding Reference

### 12.1 File & Buffer Navigation

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>f` | Find files in git root (fast) | fff.nvim |
| `<leader>F` | Find ALL files (including gitignored) | fzf-lua |
| `<leader>b` | Browse open buffers | fzf-lua |
| `<leader>p` | Search in PKB (~/pkb) | fff.nvim |
| `<leader>/` | Live grep across project | fzf-lua |
| `<leader>h` | Search help tags | fzf-lua |
| `<leader>g` | Open Grepper (advanced search) | vim-grepper |
| `-` | Open Oil file explorer | oil.nvim |

### 12.2 LSP Operations

| Key | Action | Notes |
|-----|--------|-------|
| `gd` | Go to definition | Jump to source |
| `gD` | Go to type definition | See TypeScript type |
| `gi` | Go to implementation | Skip .d.ts files |
| `gr` | Find references | Populates quickfix |
| `<leader>k` | Hover documentation | Types, JSDoc |
| `<leader>r` | Rename symbol | Project-wide |
| `<leader>x` | Code actions menu | Imports, fixes |
| `<leader>d` | Show all diagnostics | Quickfix list |
| `<leader>e` | Toggle diagnostic virtual lines | Temporary show |
| `<leader>` ` | Format current buffer | Prettier |
| `[d` / `]d` | Previous/next diagnostic | Auto-shows details |

### 12.3 Motion & Scrolling

| Key | Action |
|-----|--------|
| `s<2chars>` | Leap to location (bidirectional) |
| `<C-d>` / `<C-u>` | Scroll half page (smooth) |
| `<C-f>` / `<C-b>` | Scroll full page (smooth) |
| `<C-e>` / `<C-y>` | Scroll without moving cursor |
| `zz` / `zt` / `zb` | Center/top/bottom cursor |
| `H` / `M` / `L` | Move to screen top/middle/bottom |
| `{` / `}` | Previous/next paragraph |
| `%` | Jump to matching bracket |
| `]f` / `[f` | Next/previous function |
| `]a` / `[a` | Next/previous parameter |
| `/` / `?` | Search forward/backward |
| `*` / `#` | Search word under cursor |
| `f` / `F` / `t` / `T` | Find character on line |
| `;` / `,` | Repeat/reverse last find |

### 12.4 Text Objects (Treesitter)

| Key | Selects |
|-----|---------|
| `vif` | Inside function (body) |
| `vaf` | Around function (with declaration) |
| `vic` | Inside class |
| `vac` | Around class |
| `via` | Inside parameter |
| `vaa` | Around parameter |

### 12.5 Window Management

| Key | Action |
|-----|--------|
| `<C-h/j/k/l>` | Navigate between splits |
| `<leader>=` | Increase window height (+5) |
| `<leader>-` | Decrease window height (-5) |
| `<C-w>s` | Horizontal split |
| `<C-w>v` | Vertical split |
| `<C-w>q` | Close window |
| `<C-w>o` | Close all except current |

### 12.6 Git Operations

| Key/Command | Action |
|-------------|--------|
| `]c` / `[c` | Next/previous git hunk |
| `:Git status` | Git status |
| `:Git blame` | Line-by-line authorship |
| `:Git diff` | View changes |
| `:Gho` | Open file on GitHub |
| `:Ghl` | Open on GitHub with line number |
| `:Ghom` | Open main branch on GitHub |
| `:Ghlm` | Open main branch with line |

### 12.7 Unimpaired Navigation

| Key | Action |
|-----|--------|
| `[j` / `]j` | Jump backward/forward in jump list |
| `[J` / `]J` | Jump until buffer changes (smart!) |
| `[q` / `]q` | Previous/next quickfix item |
| `[l` / `]l` | Previous/next location list item |
| `[f` / `]f` | Older/newer quickfix list |
| `[<space>` / `]<space>` | Add blank line above/below |

### 12.8 Marks

| Key | Action |
|-----|--------|
| `m<letter>` | Set mark (lowercase=local, UPPER=global) |
| `'<letter>` | Jump to mark's line |
| `` `<letter> `` | Jump to mark's exact position |
| `''` | Jump to position before last jump |
| `'.` | Jump to last change |
| `'^` | Jump to last insert position |

---

## 13. Markdown/Text Files

### Special Mode for Prose Editing

When editing `.md` or `.txt` files, navigation becomes **visual-line aware**:

| Key | Normal Behavior | Markdown Mode |
|-----|-----------------|---------------|
| `j` / `k` | Logical lines | Visual (wrapped) lines |
| `0` / `$` | Line start/end | Visual line start/end |
| `<C-d>` / `<C-u>` | Scroll half page | Scroll by visual lines + center |

**Enabled automatically:**
- Line wrapping with `breakindent`
- Natural navigation for prose
- No need to think about line breaks

**Use case:** Writing documentation, README files, notes.

---

## 14. Advanced Features

### 14.1 AI Integration (magenta.nvim)

**Claude Opus 4.6 assistance:**
- Ask questions about code
- Explain complex functions
- Suggest refactorings
- Generate boilerplate code

**Configuration:**
- Located in `lua/config/magenta.lua`
- macOS: Direct Anthropic API
- Linux: AWS Bedrock provider
- Extended thinking enabled (1024 token budget)

**Use when:**
- Understanding unfamiliar code patterns
- Explaining error messages
- Brainstorming architecture
- Code review assistance

### 14.2 Personal Knowledge Base (PKB)

**Search your notes:** `<leader>p`

- Markdown files in `~/pkb`
- AI-powered embeddings (Cohere via Bedrock)
- Quick access to personal documentation
- Reference materials, learnings, snippets

### 14.3 Custom Motions

**T motion:** Jump to **last** occurrence of character in line
- `T<char>` - Unlike vim's default `T` (which goes backward)
- Useful for jumping to end-of-line characters

**Smart jump-until-buffer-changes:** `[J` / `]J`
- Jumps through jump list until you reach a different file
- Skips intermediate jumps within same file

### 14.4 Remote Development

**Clipboard handling for SSH/Docker:**
- **Copy (Linux)**: OSC52 escape sequences (works through tmux)
- **Paste (Linux)**: Reads from `/home/aurelia/dev-in-docker-shared-files/clipboard.txt`
- **macOS**: Standard system clipboard

**Why this matters:**
- Seamless copy/paste when developing in containers
- Works through SSH + tmux
- No X11 forwarding needed

### 14.5 Development Utilities

**In command mode:**
```vim
:lua P(value)              " Pretty print any Lua value
:lua DebugExtmarks()       " Visualize buffer extmarks
```

**Use for:**
- Debugging neovim config
- Inspecting LSP data structures
- Understanding plugin internals

---

## 15. Key Plugins

| Plugin | Purpose | Learn More |
|--------|---------|------------|
| **magenta.nvim** | AI assistant (Claude Opus 4.6) | `lua/config/magenta.lua` |
| **fff.nvim** | Fast file finder | Section 4.1 |
| **fzf-lua** | Fuzzy finder (grep, buffers) | Section 4.2 |
| **oil.nvim** | File explorer as buffer | Section 4.4 |
| **leap.nvim** | Fast motion (`s` + 2 chars) | Section 9.1 |
| **neoscroll.nvim** | Smooth scrolling | Section 9.2 |
| **nvim-lspconfig** | Language server configurations | Section 11 |
| **nvim-cmp** | Completion engine | Section 6.1 |
| **nvim-treesitter** | Syntax-aware text objects | Section 9.3 |
| **conform.nvim** | Code formatting (prettier) | Section 6.4 |
| **vim-fugitive** | Git integration | Section 8.2 |
| **gitsigns.nvim** | Git gutter signs + hunk nav | Section 8.1 |
| **vim-tmux-navigator** | Seamless vim/tmux navigation | Section 10.1 |
| **lualine.nvim** | Status line | Visual |
| **snacks.nvim** | Various utilities | Background |

---

## 16. Configuration Files Reference

### Neovim Configuration

| File | Purpose | Lines |
|------|---------|-------|
| `nvim/init.lua` | Main config, options, keymaps | 214 |
| `nvim/lua/plugins/plugins.lua` | All plugin definitions | 1089 |
| `nvim/lua/config/lazy.lua` | Plugin manager bootstrap | 44 |
| `nvim/lua/config/magenta.lua` | AI assistant config | 84 |
| `nvim/lua/dev.lua` | Development utilities | 112 |

**To modify keybindings:**
- Core mappings: `nvim/init.lua` lines 112-213
- LSP mappings: `nvim/lua/plugins/plugins.lua` in lspconfig setup
- Plugin-specific: `nvim/lua/plugins/plugins.lua` in each plugin's config

**To change AI models:**
- Edit `nvim/lua/config/magenta.lua`
- Adjust model names, thinking budgets, providers

**To change theme:**
- Uncomment desired theme in `nvim/lua/plugins/plugins.lua`
- Set `vim.cmd.colorscheme()` accordingly

### Dotfiles Structure & Nix Configuration

| File Path | What It Manages | Managed By |
|-----------|----------------|------------|
| `flake.nix` | Nix flake with macOS/Linux profiles | Nix |
| `flake.lock` | Locked dependency versions | Nix |
| `nix/common.nix` | Cross-platform packages & configs | Home Manager |
| `nix/darwin.nix` | macOS-specific setup (Homebrew, nodejs) | Home Manager |
| `nix/linux.nix` | Linux/devcontainer setup | Home Manager |
| `setup.sh` | Automated installation script | Run manually once |
| `nvim/` | Neovim configuration | Symlinked by Home Manager |
| `fish/config-darwin.fish` | macOS Fish shell config | Symlinked by Home Manager |
| `fish/config-linux.fish` | Linux Fish shell config | Symlinked by Home Manager |
| `tmux.conf` | Tmux configuration | Symlinked by Home Manager |
| `scripts/ta` | Smart tmux session manager | Symlinked to ~/.local/bin |
| `scripts/clipboard-sync` | Clipboard sync daemon | Symlinked to ~/.local/bin |
| `hammerspoon/init.lua` | macOS window management | Symlinked by Home Manager |
| `ghostty/config` | Terminal emulator config | Symlinked by Home Manager |

**Package management:**
- To add/remove packages: Edit `nix/common.nix` (or platform-specific files)
- Apply changes: `home-manager switch --flake .#macos`
- View history: `home-manager generations`
- Rollback: `home-manager switch --flake .#macos --rollback`

**Configuration management:**
- Configs are **live-linked** from dotfiles repo (not copied to Nix store)
- Edit files directly in `~/src/dlants-dotfiles/`
- Most config changes take effect immediately (just reload app)
- Package changes require Home Manager rebuild

**Language servers:**
- Installed via `nix/common.nix` in `home.packages`
- Available: TypeScript, ESLint, Lua, YAML, Bash
- To add more: Search nixpkgs.org, add to `home.packages`, rebuild

---

## 17. Troubleshooting Guide

### 17.0 Nix & Home Manager Issues

#### ⚠️ "setup.sh fails to install Nix"

**Check:**
1. Do you have admin/sudo access?
2. Is `/nix` directory writable or non-existent?
3. macOS: Is your system volume unsealed? (required for Nix)

**macOS-specific:**
```bash
# Verify system can support Nix
diskutil apfs list
# Look for "Sealed: Broken" or check if /nix can be created
```

**If Nix installation fails:**
- Review error messages carefully
- Check official Nix installation docs: https://nixos.org/download.html
- Try manual installation before running setup.sh

#### ⚠️ "Language servers not found after setup"

**Verify Home Manager installation:**
```bash
# Check if Home Manager ran successfully
home-manager generations

# Should show generation with timestamp

# Verify PATH includes Nix profile
echo $PATH | grep nix
# Should see: /nix/store/...

# Check if language servers are accessible
which typescript-language-server
# Should show: /nix/store/.../bin/typescript-language-server
```

**Rebuild if needed:**
```bash
cd ~/src/dlants-dotfiles
home-manager switch --flake .#macos  # or .#devcontainer for Linux
```

#### ⚠️ "Changes to nix/*.nix not taking effect"

**Remember:**
- **Config file edits** (nvim/, fish/, tmux.conf) take effect immediately (just reload)
- **Package changes** (nix/*.nix) require rebuild:

```bash
cd ~/src/dlants-dotfiles
home-manager switch --flake .#macos  # or .#devcontainer
```

#### ⚠️ "Neovim plugins not installing on first launch"

**On first launch:**
1. Lazy.nvim auto-installs on first Neovim start
2. Wait for all plugins to download (~30-60 seconds)
3. You may see errors during initial install - this is normal
4. Restart Neovim after plugins finish installing

**If plugins still won't install:**
```vim
# Inside Neovim
:Lazy sync
# Wait for sync to complete
# Restart Neovim
```

**Check plugin status:**
```vim
:Lazy
# See status of all plugins, install errors
```

### 17.1 LSP Issues

#### ⚠️ "typescript-language-server not executable"

**If you used setup.sh:**
Language servers are installed via Nix. Check:
```bash
# Verify language server is in PATH
which typescript-language-server
# Should show: /nix/store/.../bin/typescript-language-server

# If not found, rebuild Home Manager
cd ~/src/dlants-dotfiles
home-manager switch --flake .#macos
```

**Verify in Neovim:**
```vim
:LspInfo
# Should see: ts_ls (client id 1)
```

#### ⚠️ No autocomplete appearing

**Checklist:**
1. `:LspInfo` - Is ts_ls attached?
2. Does `tsconfig.json` exist in project root?
3. Did you run `npm install` in project?
4. Try `:LspRestart`

**Common cause:** LSP waits for `tsconfig.json` to determine project root.

#### ⚠️ `gr` (find references) shows nothing

**Debugging:**
1. `:LspInfo` - Verify LSP attached
2. `:copen` - Check if quickfix list has results
3. Try `:FzfLua lsp_references` as alternative

**If empty:**
- Symbol might only be used once (definition counts as reference)
- LSP might not have indexed all files yet (try `:LspRestart`)

#### ⚠️ `gd` opens .d.ts instead of source code

**Expected behavior:**
- For library code (react, lodash), only type definitions exist
- This is correct - you're seeing the official types

**If you want source:**
- Use `gi` (go to implementation) if available
- Or view types and press `<C-o>` to go back

### 17.2 TypeScript-Specific Issues

#### ⚠️ "Cannot find module" errors everywhere

**Solutions:**
1. Run `npm install` in project directory
2. Check `node_modules` directory exists
3. Verify import paths are correct (relative vs absolute)
4. Check `tsconfig.json` has correct `baseUrl` / `paths`

**Example tsconfig fix:**
```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  }
}
```

#### ⚠️ Type errors not showing

**Checklist:**
1. `:LspInfo` - ts_ls should show "attached"
2. Check `tsconfig.json` has `"strict": true`
3. Try `:LspRestart`
4. Check LSP logs: `:lua vim.lsp.set_log_level("debug")` then tail log

#### ⚠️ Import autocomplete broken

**Common causes:**
1. No `package.json` in project root
2. Missing `node_modules` (run `npm install`)
3. TypeScript can't resolve module (check `tsconfig.json`)

### 17.3 Plugin Issues

#### ⚠️ fff not finding files

**Troubleshooting:**
1. Are you in a git repository? (`git status`)
2. `<leader>f` respects .gitignore - use `<leader>F` to see all files
3. Check fff.nvim binary downloaded: `:checkhealth fff`

#### ⚠️ FZF not working

**Check:**
```vim
:echo executable('fzf')     " Should return 1
```

**Reinstall if needed:**
```bash
cd ~/.local/share/nvim/lazy/fzf
./install --bin
```

#### ⚠️ Leap motion (`s`) not working

**Verify:**
- Press `s` - should see "leap>" prompt
- Plugin might need to be loaded manually first time

**Reinstall:**
```vim
:Lazy sync leap.nvim
```

### 17.4 Performance Problems

#### ⚠️ Slow startup

**Diagnosis:**
```vim
:Lazy profile     " See plugin load times
```

**Common causes:**
- Too many plugins loading eagerly (should be lazy-loaded)
- Large files in project (bigfile detection should help)
- Treesitter parsing large files

#### ⚠️ Lag when typing in TypeScript files

**Solutions:**
1. Check file size - treesitter disabled for files > 100KB automatically
2. Reduce LSP debounce time if too aggressive
3. `:LspStop` temporarily to test if LSP is cause

#### ⚠️ High memory usage

**Check:**
```vim
:lua print(vim.loop.resident_set_memory() / 1024 / 1024 .. " MB")
```

**Common causes:**
- Many buffers open (close unused with `:bdelete`)
- LSP indexing large projects
- Multiple LSP servers running

---

## 18. Quick Reference Cards

### Essential Daily Keybindings

**Finding Code:**
- `<leader>f` - Find files
- `<leader>/` - Search in files
- `<leader>b` - Switch buffers

**Understanding Code:**
- `gd` - Go to definition
- `gr` - Find references
- `<leader>k` - Documentation

**Editing Code:**
- `<leader>r` - Rename
- `<leader>x` - Code actions
- `<leader>` ` - Format

**Fixing Errors:**
- `]d` / `[d` - Jump errors
- `<leader>d` - List all errors
- `:copen` - Open quickfix

**Navigation:**
- `s<2chars>` - Leap anywhere
- `]f` / `[f` - Next/prev function
- `zz` - Center screen

**Git:**
- `]c` / `[c` - Next/prev hunk
- `:Git` - Git commands
- `:Gho` - GitHub browse

### TypeScript LSP Cheatsheet

```bash
# Install
npm install -g typescript typescript-language-server

# Verify
:LspInfo

# Common Issues
:LspRestart           # Restart LSP
:checkhealth lsp      # Check LSP health
```

**Key bindings:**
- `gd` - Definition
- `gD` - Type definition
- `gi` - Implementation
- `gr` - References (then :copen)
- `<leader>r` - Rename
- `<leader>x` - Quick fix

### Unimpaired Navigation Patterns

```
[ ]         Navigation prefix
  j/J       Jump list (J = until buffer changes)
  d         Diagnostics (errors/warnings)
  c         Git hunks (changes)
  q         Quickfix list
  l         Location list
  f         Quickfix file (older/newer list)
  <space>   Add blank lines
```

**Mental model:** `[` goes backward/previous, `]` goes forward/next in any list.

---

## 19. Beyond Neovim: Other Dotfiles Components

This repository includes a complete development environment. Here's what else is configured:

### 19.1 Fish Shell

**Location:** `fish/config-darwin.fish` (or `config-linux.fish`)

**Features:**
- Vi key bindings (`fish_vi_key_bindings`)
- Custom git function: `git-clean-branches` - Delete merged branches
- Aliases: `vi` → `nvim`, `rm` → `rm -I` (safer deletion)
- Integration with OrbStack (macOS)/Docker
- Custom title function for tmux pane naming

**Usage:**
Config is live-linked, so edit directly:
```bash
nvim ~/src/dlants-dotfiles/fish/config-darwin.fish
# Changes take effect in new shell sessions
```

### 19.2 Tmux

**Location:** `tmux.conf`

**Features:**
- **Seamless vim integration:** `<C-h/j/k/l>` works across vim splits AND tmux panes
- **Remote development:** OSC52 clipboard support for SSH
- **FZF session switcher:** `ctrl-b o` for fuzzy session selection
- **Vi mode:** Copy mode uses vi bindings
- **Theming:** Flow colorscheme (matches Neovim)

**Common workflows:**
```bash
# Create/attach to named session
tmux new -s myproject

# Or use the smart session manager (see 19.3)
ta ~/projects/myapp           # Local session
ta dev:/home/user/project     # Remote SSH session
```

### 19.3 Smart Session Manager (`ta` script)

**Location:** `scripts/ta`

**What it does:**
- Creates tmux sessions tied to directories (local or remote)
- Automatically SSH to remote hosts
- Persistent sessions survive disconnects
- Integrates with clipboard sync daemon

**Usage:**
```bash
# Local session
ta ~/my-project
# Creates session named "my-project" with cwd set

# Remote session
ta dev:/home/mugabo/webapp
# SSH to 'dev' host, create session, set cwd to /home/mugabo/webapp
# All new windows auto-SSH back to same host!
```

**Special features:**
- Session names based on directory (e.g., `ta ~/work/app` → session "app")
- Attaches if session already exists
- Works with `.ssh/config` host aliases
- Clipboard sync daemon auto-starts for remote sessions

### 19.4 Hammerspoon (macOS Only)

**Location:** `hammerspoon/init.lua`

**Features:**
- Window management shortcuts (Cmd+Alt+←/→ for half-screen)
- IPC support for CLI control
- Auto-reload on config changes
- Custom hotkeys for app switching

**Setup:**
Installed via Homebrew by `nix/darwin.nix`, config symlinked automatically.

**Common keybindings:**
- `Cmd+Alt+Left` - Snap window to left half
- `Cmd+Alt+Right` - Snap window to right half
- `Cmd+Alt+F` - Fullscreen toggle

### 19.5 Ghostty Terminal (macOS Only)

**Location:** `ghostty/config`

**Features:**
- GPU-accelerated rendering
- Custom themes matching Neovim (Flow colorscheme)
- Custom shaders for visual effects
- Font configuration optimized for coding
- Integration with tmux

**Theming:**
Themes defined in `ghostty/themes/`, shaders in `ghostty/shaders/`

### 19.6 Clipboard Sync (for Remote Dev)

**Location:** `scripts/clipboard-sync`

**How it works:**
- **macOS:** Daemon watches clipboard, writes to shared file
- **Linux container:** Reads from shared file for paste operations
- Enables copy/paste across Docker/SSH boundaries

**When it runs:**
- Auto-starts when using `ta` for remote sessions
- macOS: Monitors clipboard every 0.5s
- Linux: Neovim reads from `/home/aurelia/dev-in-docker-shared-files/clipboard.txt`

**Debugging:**
See `notes/clipboard-setup.md` and `tmux-clipboard-debug.md` in the repo.

### 19.7 Updating Dotfiles Configuration

**For config files (nvim/, fish/, tmux.conf):**
```bash
# Edit directly - changes take effect immediately
nvim ~/src/dlants-dotfiles/nvim/init.lua
# Restart Neovim to apply changes
```

**For packages (nix/*.nix):**
```bash
# 1. Edit Nix configuration
nvim ~/src/dlants-dotfiles/nix/common.nix

# 2. Rebuild Home Manager
cd ~/src/dlants-dotfiles
home-manager switch --flake .#macos  # or .#devcontainer

# 3. New packages are now in PATH
```

**To see what changed:**
```bash
# List Home Manager generations
home-manager generations

# Rollback to previous generation if needed
home-manager switch --flake .#macos --rollback
```

---

## 20. Learning Path

### Day 1: Essentials
- [ ] Run `./setup.sh` for automated installation
- [ ] Verify Neovim opens and plugins install
- [ ] Learn `<leader>f` and `<leader>/`
- [ ] Practice `gd` and `<C-o>`
- [ ] Try `s` + 2 chars for leap motion

### Week 1: Navigation
- [ ] Master `gd`, `gr`, `<leader>k`
- [ ] Learn `]d` / `[d` for errors
- [ ] Practice `]q` / `[q` in quickfix
- [ ] Try `]f` / `[f` for function jumping

### Week 2: Editing
- [ ] Use `<leader>r` for renaming
- [ ] Practice `<leader>x` for quick fixes
- [ ] Format with `<leader>` `
- [ ] Experiment with text objects (`vif`, `vac`)

### Week 3: Advanced
- [ ] Learn Oil for file operations
- [ ] Try `[J` / `]J` smart jumping
- [ ] Explore git workflow (`:Git`, hunks)
- [ ] Customize keybindings if needed

### Month 2+: Power User
- [ ] Use AI assistance for complex tasks
- [ ] Master all unimpaired navigation
- [ ] Create PKB for learnings
- [ ] Share workflow with team

---

**You're ready to start!** Begin with the [Quick Start Checklist](#2-quick-start-checklist) and practice the [Essential 10 Keybindings](#-your-first-week-essential-10-keybindings) today.
