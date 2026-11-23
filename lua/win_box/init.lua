local boundary = require("win_box.boundary")
local picker = require("win_box.picker")
local actions = require("win_box.actions")
local ratio = require("win_box.ratio")
local keys = require("win_box.keys")
local M = {}

local defaults = {
  boundary = true,
  keep_ratio = true,
  picker = { style = "plain" },
  ignore_filetypes = { "TelescopePrompt" },
  highlights = { boundary = "DiagnosticInfo", adjust_boundary = "DiagnosticWarn", picker = "IncSearch" },
}
local options = defaults

local function apply_colors()
  for key, name in pairs({
    boundary = "WinBoxBoundary",
    adjust_boundary = "WinBoxAdjustBoundary",
    picker = "WinBoxPicker",
  }) do
    local value = options.highlights[key]
    vim.api.nvim_set_hl(0, name, type(value) == "string" and { link = value } or value)
  end
end

function M.setup(opts)
  opts = opts or {}
  local configured_keys = keys.compile(opts.keys)
  local configured = vim.tbl_deep_extend("force", {}, defaults, opts)
  assert(type(configured.picker) == "table"
      and (configured.picker.style == "plain" or configured.picker.style == "large"),
    'win-box: picker.style must be "plain" or "large"')
  options = configured
  keys.current = configured_keys
  picker.style = options.picker.style
  apply_colors()
  local group = vim.api.nvim_create_augroup("WinBox", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = apply_colors })
  if options.keep_ratio then
    ratio.remember()
    vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinResized" }, {
      group = group,
      callback = function() vim.schedule(ratio.remember) end,
    })
    vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, { group = group, callback = ratio.restore })
  end
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "VimResized", "BufWinEnter", "FileType", "ColorScheme" }, {
    group = group,
    callback = function() boundary.schedule(options) end,
  })
  boundary.schedule(options)
end

function M.pick()
  return picker.pick(true)
end

function M.adjust()
  if not boundary.set_adjusting(true) then return false end
  local function redraw()
    boundary.draw(options)
    vim.cmd.redraw()
  end
  local ok, result = pcall(actions.adjust, redraw)
  boundary.set_adjusting(false)
  redraw()
  if not ok then error(result, 0) end
  if result and options.keep_ratio then ratio.remember() end
  return result
end

M.focus = actions.focus
M.resize = actions.resize
function M.swap_windows(other)
  local swapped = actions.swap_windows(other)
  if swapped then
    if options.keep_ratio then
      ratio.remember()
    end
    boundary.schedule(options)
  end
  return swapped
end

function M.move(direction)
  if type(direction) ~= "string" then return false end
  return M.swap_windows(direction)
end

M.swap = M.swap_windows
M.swap_buffers = actions.swap_buffers

return M
