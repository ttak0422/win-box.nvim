local layout = require("win_box.layout")
local M = {}
local overlays = {}
local pending = false
local drawing = false

local function add(ranges, axis, start, stop, cell)
  if start < stop then
    ranges[#ranges + 1] = { axis = axis, start = start, stop = stop, cell = cell }
  end
end

local function blank_separator(win)
  return vim.wo[win].statusline:match("^%s*%%=%s*$") ~= nil
end

function M.segments(focused, windows, horizontal)
  local function can_paint(upper)
    return horizontal == true or (horizontal == "blank" and blank_separator(upper))
  end
  local ranges = {}
  local a = layout.rect(focused)
  for _, win in ipairs(windows) do
    if win ~= focused then
      local b = layout.rect(win)
      local top, bottom = math.max(a.top, b.top), math.min(a.bottom, b.bottom)
      if a.right + 1 == b.left then
        add(ranges, "v", top, bottom, a.right)
      elseif b.right + 1 == a.left then
        add(ranges, "v", top, bottom, b.right)
      end
      local left, right = math.max(a.left, b.left), math.min(a.right, b.right)
      if a.bottom + 1 == b.top and can_paint(focused) then
        add(ranges, "h", left, right, a.bottom)
      elseif b.bottom + 1 == a.top and can_paint(win) then
        add(ranges, "h", left, right, b.bottom)
      end
    end
  end
  return ranges
end

function M.clear()
  for _, item in ipairs(overlays) do
    if vim.api.nvim_win_is_valid(item.win) then
      pcall(vim.api.nvim_win_close, item.win, true)
    end
  end
  overlays = {}
end

local function draw(options)
  M.clear()
  local wins = layout.windows()
  local active = vim.api.nvim_get_current_win()
  if not options.boundary or not vim.tbl_contains(wins, active) or #wins < 2
    or vim.tbl_contains(options.ignore_filetypes, vim.bo.filetype) then
    return
  end
  local fill = vim.opt.fillchars:get()
  -- Paint native horizontal separators, or an explicitly empty statusline
  -- in the no-final-statusline layout. Leave content-bearing lines untouched.
  local horizontal = vim.o.laststatus == 3 or (vim.o.laststatus == 0 and "blank")
  for _, range in ipairs(M.segments(active, wins, horizontal)) do
    local vertical = range.axis == "v"
    local length = range.stop - range.start
    local char = vertical and (fill.vert or "│") or (fill.horiz or "─")
    if vim.fn.strdisplaywidth(char) ~= 1 then
      char = vertical and "|" or "-"
    end
    local lines = {}
    for i = 1, vertical and length or 1 do
      lines[i] = vertical and char or char:rep(length)
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
      relative = "editor",
      row = vertical and range.start or range.cell,
      col = vertical and range.cell or range.start,
      width = vertical and 1 or length,
      height = vertical and length or 1,
      border = "none", -- Separator cells must not inherit the global float frame.
      style = "minimal",
      focusable = false,
      mouse = false,
      zindex = 1,
      noautocmd = true,
    })
    if ok then
      vim.wo[win].winhighlight = "Normal:WinBoxBoundary,NormalNC:WinBoxBoundary"
      overlays[#overlays + 1] = { win = win }
    else
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

function M.draw(options)
  drawing = true
  local ok, err = pcall(draw, options)
  drawing = false
  if not ok then
    vim.notify("win-box boundary: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.schedule(options)
  if pending or drawing then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.draw(options)
  end)
end

return M
