# win-box.nvim

Window selection, split adjustment, and focused split borders for Neovim 0.12 and later. The plugin does not register key mappings.

## Setup

```lua
local win_box = require("win_box")
win_box.setup({
  boundary = true,
  keep_ratio = true,
  ignore_filetypes = { "TelescopePrompt" },
  highlights = {
    boundary = "DiagnosticInfo",
    adjust_boundary = "DiagnosticWarn",
    picker = { fg = "#ffffff", bg = "#355c88", bold = true },
  },
})
```

Highlights accept a group name or a highlight table. They apply only to the plugin's borders and labels. Focused shared edges use heavy one-cell lines where supported, falling back to a one-cell separator. Existing split junctions join the heavy focused edges to the lighter neighboring edges. No exterior or floating pane frame is added. Horizontal edges are colored with a global statusline (`laststatus=3`), or when `laststatus=0` and the separator window explicitly uses the blank statusline `%=`. Content-bearing statuslines are left alone. During `adjust()`, the same edges use `highlights.adjust_boundary` and return to `highlights.boundary` when resizing ends. Both respect `boundary = false` and `ignore_filetypes`.

## Picker appearance

The default picker shows a single character. Use
`win_box.setup({ picker = { style = "large" } })` for centered,
multi-line **ANSI Compact** letters and digits surrounded by a thin frame.
The picker includes a subset of Loic Cressot's [MIT-licensed font](LICENSES/ANSI-Compact-MIT.txt), with no
font file or FIGlet program needed at runtime. Narrow or short panes and
unsupported label characters use a borderless single-character hint. The existing
`highlights.picker` option colors both styles and the large hint frame.

## Modal keys

Keys are read only while `adjust()` or a picker is open. This does not install,
remove, or override any editor mappings. Omitted fields preserve the defaults;
an action accepts one key, a list of alternatives, or `false` to disable it.
Use Neovim notation such as `<Right>` for special keys, not multi-key sequences.

```lua
win_box.setup({
  keys = {
    adjust = {
      left = { "a", "<Left>" },
      down = { "s", "<Down>" },
      up = { "w", "<Up>" },
      right = { "d", "<Right>" },
      confirm = "<CR>",
      cancel = { "x", "<Esc>" },
    },
    picker = {
      labels = "asdf", -- or an array of single-cell characters
      cancel = { "q", "<Esc>" },
    },
  },
})
```

The default resize bindings are `h/j/k/l` and arrows, Enter for confirm,
and `q`, Escape or Ctrl-C for cancel. At least one
confirm or cancel key is required. Keys must not overlap between actions.
The picker lists windows with configurable labels; any key without a label
cancels it. Set `keys.picker.labels = false` to disable label selection; operations
given an explicit target still work.

## Operations

- `pick()`: display labels in the current tab's split windows. Enter a label to focus it, or Escape to cancel.
- `adjust()`: resize the current split with `hjkl` or arrow keys. Changes take effect immediately. Enter keeps them; `q` or Escape restores the original sizes.
- `focus(dir)`, `resize(dir, amount)`: act on the current split. Directions are `left`, `down`, `up`, `right` (or `hjkl`).
- `move(dir)`: shift the focused window one step through the split hierarchy, optionally forming a new row or column. This does not select a swap target. The original window retains focus.
- `swap([target])` / `swap_windows([target])`: exchange whole windows, including across split groups. Omit the target to show the picker; a window ID or direction can also be passed. If the available space cannot accommodate the temporary split anchors, the operation returns false without swapping buffers instead.
- `swap_buffers([target])`: exchange only buffers and views. Does not bypass fixed buffers or discard buffers with destructive `bufhidden` settings.
- `keep_ratio`: preserve each tab's split widths on editor resize, respecting fixed widths and Neovim's minimum window sizes. Very small sizes are best-effort.

Optional key bindings:

```lua
vim.keymap.set("n", "<C-w>p", win_box.pick)
vim.keymap.set("n", "<C-w>e", win_box.adjust)
vim.keymap.set("n", "<C-w><C-w>", function() win_box.swap() end)
```

## Tests

```sh
nvim --headless -u NONE -i NONE -l tests/smoke.lua
python3 tests/multigrid.py  # Python msgpack is required
```
