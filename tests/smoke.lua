-- Run from the repository root: nvim --headless -u NONE -i NONE -l tests/smoke.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local wb = require("win_box")
local layout = require("win_box.layout")
local boundary = require("win_box.boundary")
local api = vim.api
local function win()
  return api.nvim_get_current_win()
end
local function keys(s)
  api.nvim_feedkeys(api.nvim_replace_termcodes(s, true, false, true), "n", false)
end
local old = vim.fn.maparg("<C-w>p", "n")
wb.setup({ highlights = { boundary = { fg = "#abcdef" }, picker = "Visual" } })
assert(vim.fn.maparg("<C-w>p", "n") == old, "setup must not touch maps")
assert(api.nvim_get_hl(0, { name = "WinBoxBoundary" }).fg == 0xabcdef)
assert(api.nvim_get_hl(0, { name = "WinBoxPicker", link = true }).link == "Visual")

vim.o.splitright = true
local left = win()
local left_buf = api.nvim_get_current_buf()
vim.cmd.vnew()
local right = win()
local right_buf = api.nvim_get_current_buf()
assert(wb.focus("left") and win() == left)
local size = api.nvim_win_get_width(left)
assert(wb.resize("right", 4))
assert(api.nvim_win_get_width(left) == size + 4)
local resize_baseline = layout.snapshot()
local resize_tree = vim.fn.winlayout()
keys("llq") -- Cancel restores the original dimensions.
assert(not wb.adjust())
assert(win() == left and vim.deep_equal(layout.snapshot(), resize_baseline))
assert(vim.deep_equal(vim.fn.winlayout(), resize_tree))
keys("el<CR>") -- Former cycle key is ignored; direction still resizes.
assert(wb.adjust() and win() == left)
assert(api.nvim_win_get_width(left) == resize_baseline[left].width + 1)
assert(vim.deep_equal(vim.fn.winlayout(), resize_tree))

assert(wb.swap_windows(right))
assert(layout.rect(left).left > layout.rect(right).left and win() == left)
assert(wb.swap_windows(right))
assert(layout.rect(left).left < layout.rect(right).left and win() == left)
assert(wb.swap_buffers("right"))
assert(api.nvim_win_get_buf(left) == right_buf and api.nvim_win_get_buf(right) == left_buf)
assert(wb.swap_buffers(right))
assert(api.nvim_win_get_buf(left) == left_buf and api.nvim_win_get_buf(right) == right_buf)
keys("s")
assert(wb.pick() == right and win() == right)
keys("<Esc>")
assert(wb.pick() == nil and win() == right)
local left_slot, right_slot = layout.rect(left), layout.rect(right)
assert(wb.move("left"))
assert(win() == right and vim.deep_equal(layout.rect(right), left_slot))
assert(vim.deep_equal(layout.rect(left), right_slot))
assert(wb.move("right"))
assert(win() == right and vim.deep_equal(layout.rect(right), right_slot))
assert(vim.deep_equal(layout.rect(left), left_slot))
api.nvim_set_current_win(left)
local segments = boundary.segments(left, layout.windows(), false)
assert(#segments == 1 and segments[1].axis == "v", vim.inspect(segments))
boundary.draw({ boundary = true, ignore_filetypes = {} })
local overlays = #api.nvim_tabpage_list_wins(0) - #layout.windows()
assert(overlays == 1)
vim.wait(40, function() return false end)
assert(#api.nvim_tabpage_list_wins(0) == #layout.windows() + overlays, "boundary churn")
boundary.clear()

-- Mixed split: focus a short upper pane and ensure no full-height border.
api.nvim_set_current_win(left)
vim.o.splitbelow = true
vim.cmd.new()
local bottom_left = win()
local top_left = left
local mixed = boundary.segments(top_left, layout.windows(), true)
assert(#mixed > 0)
local expected = layout.rect(top_left)
for _, segment in ipairs(mixed) do
  if segment.axis == "v" then
    assert(segment.start >= expected.top and segment.stop <= expected.bottom)
  end
end
assert(vim.tbl_contains(layout.windows(), bottom_left))
-- Cross-group swap moves window IDs and their local options, not just buffers.
api.nvim_set_current_win(top_left)
vim.wo[top_left].winbar = "WINBOX_HUD"
vim.wo[top_left].cursorline = true
vim.wo[right].cursorline = false
local before_swap = { layout.rect(top_left), layout.rect(right) }
local old_ignore = vim.o.eventignore
local before_tree = vim.fn.winlayout()
local first_buffer, second_buffer = api.nvim_win_get_buf(top_left), api.nvim_win_get_buf(right)
assert(wb.swap(right))
assert(win() == top_left)
assert(api.nvim_win_get_buf(top_left) == first_buffer and api.nvim_win_get_buf(right) == second_buffer)
assert(vim.wo[top_left].winbar == "WINBOX_HUD" and vim.wo[top_left].cursorline and not vim.wo[right].cursorline)
assert(vim.deep_equal(layout.rect(top_left), before_swap[2]))
assert(vim.deep_equal(layout.rect(right), before_swap[1]))
assert(vim.o.eventignore == old_ignore)
assert(wb.swap(right) and vim.deep_equal(vim.fn.winlayout(), before_tree))

-- A rejected creation or move does not degrade into a buffer-only swap or
-- leave temporary windows/options behind.
local function reject_second(method)
  local original, attempts = api[method], 0
  api[method] = function(...)
    attempts = attempts + 1
    if attempts == 2 then error("fixture: reject the second " .. method) end
    return original(...)
  end
  local swapped = wb.swap(right)
  api[method] = original
  assert(attempts >= 2 and not swapped)
  assert(vim.deep_equal(vim.fn.winlayout(), before_tree) and win() == top_left)
  assert(vim.o.eventignore == old_ignore)
  assert(api.nvim_win_get_buf(top_left) == first_buffer and api.nvim_win_get_buf(right) == second_buffer)
end
reject_second("nvim_open_win")
reject_second("nvim_win_set_config")

vim.o.laststatus = 0
vim.wo[top_left].statusline = "%="
local blank = boundary.segments(top_left, layout.windows(), "blank")
assert(vim.iter(blank):any(function(edge) return edge.axis == "h" end))
vim.wo[top_left].statusline = "STATUSLINE_HAS_CONTENT"
local content = boundary.segments(top_left, layout.windows(), "blank")
assert(vim.iter(content):all(function(edge) return edge.axis ~= "h" end))
-- Modal overrides do not affect global or buffer-local mappings.
vim.keymap.set("n", "x", function() error("external map was run") end)
vim.keymap.set("n", "a", "b", { buffer = api.nvim_get_current_buf() })
local global_maps = api.nvim_get_keymap("n")
local current_buf = api.nvim_get_current_buf()
local local_maps = api.nvim_buf_get_keymap(current_buf, "n")
wb.setup({ keys = {
  adjust = { left = false, right = "a", confirm = "!", cancel = "x" },
  picker = { labels = { "u", "v", "w" }, cancel = "p" },
} })
assert(vim.deep_equal(api.nvim_get_keymap("n"), global_maps))
assert(vim.deep_equal(api.nvim_buf_get_keymap(current_buf, "n"), local_maps))
local custom_base = layout.snapshot()
keys("aax")
assert(not wb.adjust() and vim.deep_equal(layout.snapshot(), custom_base))
keys("h<Left>l<Right>!") -- disabled left, replaced right, and removed fallback aliases
assert(wb.adjust() and vim.deep_equal(layout.snapshot(), custom_base))
keys("a!")
assert(wb.adjust() and win() == top_left)
assert(api.nvim_win_get_width(top_left) == custom_base[top_left].width + 1)
assert(wb.focus("right") and win() == right)
keys("p")
assert(not wb.pick() and win() == right)
keys("u")
assert(wb.pick() == layout.windows()[1])
assert(vim.deep_equal(api.nvim_get_keymap("n"), global_maps))
assert(vim.deep_equal(api.nvim_buf_get_keymap(current_buf, "n"), local_maps))

wb.setup({ keys = { adjust = { confirm = false }, picker = { labels = false } } })
assert(not wb.pick() and not wb.swap())
local disabled = layout.snapshot()
keys("q")
assert(not wb.adjust() and vim.deep_equal(layout.snapshot(), disabled))
assert(not pcall(wb.setup, { keys = { adjust = { confirm = false, cancel = false } } }))
assert(not pcall(wb.setup, { keys = { adjust = { left = "jj" } } }))
assert(not pcall(wb.setup, { keys = { adjust = { left = "j" } } }))
-- Moving the upper-left pane of the right group left swaps it with the
-- full-height left pane, without changing the geometry of the four slots.
vim.cmd.tabnew()
wb.setup({ boundary = false })
vim.o.equalalways = false
local license = win()
vim.cmd("rightbelow vnew")
local lower = win()
vim.cmd("leftabove new")
local readme = win()
vim.cmd("rightbelow vnew")
local upper_right = win()
api.nvim_win_set_width(license, 23)
api.nvim_win_set_width(readme, 17)
api.nvim_set_current_win(readme)
local readme_buf = api.nvim_win_get_buf(readme)
local license_buf = api.nvim_win_get_buf(license)
local rectangles = {}
for _, id in ipairs({ readme, license, lower, upper_right }) do
  rectangles[id] = layout.rect(id)
end
assert(wb.move("left") and win() == readme)
local expected_move = { "row", {
  { "leaf", readme },
  { "col", {
    { "row", { { "leaf", license }, { "leaf", upper_right } } },
    { "leaf", lower },
  } },
} }
assert(vim.deep_equal(vim.fn.winlayout(), expected_move), vim.inspect(vim.fn.winlayout()))
assert(vim.deep_equal(layout.rect(readme), rectangles[license]))
assert(vim.deep_equal(layout.rect(license), rectangles[readme]))
assert(vim.deep_equal(layout.rect(lower), rectangles[lower]))
assert(vim.deep_equal(layout.rect(upper_right), rectangles[upper_right]))
assert(api.nvim_win_get_buf(readme) == readme_buf and api.nvim_win_get_buf(license) == license_buf)
assert(not wb.move("left") and win() == readme)
assert(vim.deep_equal(vim.fn.winlayout(), expected_move))

print("win-box smoke: maps, colors, pick, adjust, edges, directional moves, swaps and modal key configuration")
