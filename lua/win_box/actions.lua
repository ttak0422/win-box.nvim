local layout = require("win_box.layout")
local picker = require("win_box.picker")
local exchange = require("win_box.exchange")
local keys = require("win_box.keys")
local M = {}
local aliases = { left = "h", down = "j", up = "k", right = "l" }
local splits = { h = "left", j = "below", k = "above", l = "right" }
local opposite = { h = "l", j = "k", k = "j", l = "h" }

local function direction_key(direction)
  return aliases[direction] or direction
end

local function neighbor(win, key)
  if not opposite[key] or not vim.tbl_contains(layout.windows(), win) then
    return nil
  end
  return vim.api.nvim_win_call(win, function()
    local next_win = vim.fn.win_getid(vim.fn.winnr(key))
    return next_win ~= win and next_win or nil
  end)
end

function M.focus(direction)
  local target = neighbor(vim.api.nvim_get_current_win(), direction_key(direction))
  if target then
    vim.api.nvim_set_current_win(target)
    return true
  end
  return false
end

function M.resize(direction, amount)
  local key = direction_key(direction)
  local horizontal = key == "h" or key == "l"
  local win = vim.api.nvim_get_current_win()
  local pos, neg = horizontal and "l" or "j", horizontal and "h" or "k"
  local sign = key == pos and 1 or -1
  if not neighbor(win, pos) then
    if not neighbor(win, neg) then
      return false
    end
    sign = -sign
  end
  local axis = horizontal and "width" or "height"
  if not opposite[key] or vim.wo[win]["winfix" .. axis] then
    return false
  end
  local get, set = vim.api["nvim_win_get_" .. axis], vim.api["nvim_win_set_" .. axis]
  local size = get(win)
  local ok = pcall(set, win, math.max(1, size + sign * (amount or 1)))
  return ok and get(win) ~= size
end

function M.move(direction)
  local key = direction_key(direction)
  local win = vim.api.nvim_get_current_win()
  local target = neighbor(win, key)
  if not target then
    return false
  end
  local ok = pcall(vim.api.nvim_win_set_config, win, { win = target, split = splits[key] })
  return ok
end

local function swap_target(win, other)
  if type(other) == "string" then
    return neighbor(win, direction_key(other))
  end
  return other or picker.pick(false, win)
end

function M.swap_buffers(other)
  local win = vim.api.nvim_get_current_win()
  other = swap_target(win, other)
  local wins = layout.windows()
  if other == win or not vim.tbl_contains(wins, win) or not vim.tbl_contains(wins, other) then
    return false
  end
  local a, b = vim.api.nvim_win_get_buf(win), vim.api.nvim_win_get_buf(other)
  if vim.wo[win].winfixbuf or vim.wo[other].winfixbuf
      or a == b or vim.bo[a].bufhidden == "wipe" or vim.bo[b].bufhidden == "wipe"
      or vim.bo[a].bufhidden == "delete" or vim.bo[b].bufhidden == "delete"
      or vim.bo[a].bufhidden == "unload" or vim.bo[b].bufhidden == "unload" then
    return false
  end
  local av = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local bv = vim.api.nvim_win_call(other, vim.fn.winsaveview)
  local ok = pcall(function()
    vim.api.nvim_win_set_buf(win, b)
    vim.api.nvim_win_set_buf(other, a)
    assert(vim.api.nvim_win_get_buf(win) == b and vim.api.nvim_win_get_buf(other) == a)
    vim.api.nvim_win_call(win, function() vim.fn.winrestview(bv) end)
    vim.api.nvim_win_call(other, function() vim.fn.winrestview(av) end)
  end)
  if not ok then
    pcall(vim.api.nvim_win_set_buf, win, a)
    pcall(vim.api.nvim_win_set_buf, other, b)
  end
  return ok
end

function M.swap_windows(other)
  local win = vim.api.nvim_get_current_win()
  other = swap_target(win, other)
  return other ~= nil and exchange.swap(win, other)
end

local modes = { "resize", "move", "focus" }

function M.adjust(redraw)
  local origin = vim.api.nvim_get_current_win()
  if not vim.tbl_contains(layout.windows(), origin) or #layout.windows() < 2 then
    return false
  end
  local dimensions = layout.snapshot()
  local restore = vim.fn.winrestcmd()
  local mode, deferred = 1, {}
  local bindings = keys.current.adjust
  local hints, arrows = {}, {}
  for _, name in ipairs({ "left", "down", "up", "right" }) do
    local key = bindings.labels[name][1]
    if key then arrows[#arrows + 1] = key end
  end
  if #arrows > 0 then hints[#hints + 1] = table.concat(arrows, " ") end
  for _, name in ipairs({ "cycle", "confirm", "cancel" }) do
    local key = bindings.labels[name][1]
    if key then hints[#hints + 1] = key .. " " .. name end
  end
  local prompt = table.concat(hints, " · ")
  local ok, accepted = pcall(function()
    while true do
      local message = "win-box " .. modes[mode] .. (#deferred > 0 and " (" .. #deferred .. " queued)" or "")
        .. " · " .. prompt
      local width = math.max(1, vim.o.columns - 2)
      if vim.fn.strdisplaywidth(message) > width then
        message = vim.fn.strcharpart(message, 0, width)
        while vim.fn.strdisplaywidth(message) > width do
          message = vim.fn.strcharpart(message, 0, vim.fn.strchars(message) - 1)
        end
      end
      vim.api.nvim_echo({ { message, "ModeMsg" } }, false, {})
      redraw()
      local action = bindings.bindings[vim.fn.keytrans(vim.fn.getcharstr())]
      if action == "confirm" then
        return true
      elseif action == "cancel" then
        return false
      elseif action == "cycle" then
        mode = mode % #modes + 1
      elseif action and aliases[action] then
        if mode == 2 then
          deferred[#deferred + 1] = { win = vim.api.nvim_get_current_win(), key = action }
        else
          M[modes[mode]](action)
        end
      end
    end
  end)
  vim.api.nvim_echo({ { "" } }, false, {})
  if ok and accepted then
    local active = vim.api.nvim_get_current_win()
    for _, step in ipairs(deferred) do
      if vim.api.nvim_win_is_valid(step.win) then
        vim.api.nvim_set_current_win(step.win)
        M.move(step.key)
      end
    end
    if vim.api.nvim_win_is_valid(active) then
      vim.api.nvim_set_current_win(active)
    end
  else
    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
    if #vim.tbl_keys(dimensions) == #layout.windows()
      and vim.iter(layout.windows()):all(function(win) return dimensions[win] ~= nil end) then
      if not pcall(vim.cmd, restore) then
        layout.restore_dimensions(dimensions)
      end
    end
  end
  redraw()
  return ok and accepted == true
end

return M
