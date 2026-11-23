local M = {}
local api = vim.api
local sides = { row = { "left", "right" }, col = { "above", "below" } }

local function slot(tree, win, parent)
  if tree[1] == "leaf" then
    return tree[2] == win and parent or nil
  end
  for _, child in ipairs(tree[2]) do
    local result = slot(child, win, tree)
    if result then return result end
  end
end

local function replace(tree, a, b)
  if tree[1] == "leaf" then
    local win = tree[2]
    return { "leaf", win == a and b or win == b and a or win }
  end
  return { tree[1], vim.tbl_map(function(child) return replace(child, a, b) end, tree[2]) }
end

local function without(tree, omitted)
  if tree[1] == "leaf" then
    return not omitted[tree[2]] and tree or nil
  end
  local children = {}
  for _, child in ipairs(tree[2]) do
    local result = without(child, omitted)
    if result then children[#children + 1] = result end
  end
  if #children == 1 then return children[1] end
  if #children > 1 then return { tree[1], children } end
end

local function pad(win, split)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local ok, result = pcall(api.nvim_open_win, buf, false, { win = win, split = split, noautocmd = true })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    error(result)
  end
  return result
end

function M.swap(a, b)
  local before = vim.fn.winlayout()
  local a_parent, b_parent = slot(before, a), slot(before, b)
  if a == b or not a_parent or not b_parent then return false end
  local expected = replace(before, a, b)
  local dimensions = vim.fn.winrestcmd()
  if a_parent == b_parent then
    local ok = pcall(vim.cmd.wincmd, { args = { "x" }, count = vim.fn.win_id2win(b) })
    if api.nvim_win_is_valid(a) then api.nvim_set_current_win(a) end
    if not ok or not vim.deep_equal(vim.fn.winlayout(), expected) then return false end
    -- Native exchange carries the sizes with the windows. Restore each slot
    -- by position, matching the cross-group swap.
    pcall(vim.cmd, dimensions)
    return true
  end

  -- Anchor both slots with an adjacent scratch split before moving either
  -- window. Both native window IDs, and their views/options, survive the move.
  local first, second = sides[a_parent[1]], sides[b_parent[1]]
  local a_pad, b_pad, moved_a, moved_b
  local ignore = vim.o.eventignore
  vim.opt.eventignore:append({ "WinNew", "WinClosed", "WinEnter", "WinLeave",
    "BufEnter", "BufLeave", "BufWinEnter", "BufWinLeave" })
  local ok = pcall(function()
    a_pad = pad(a, first[1])
    b_pad = pad(b, second[1])
    api.nvim_win_set_config(a, { win = b_pad, split = second[2] })
    moved_a = true
    api.nvim_win_set_config(b, { win = a_pad, split = first[2] })
    moved_b = true
    assert(vim.deep_equal(without(vim.fn.winlayout(), { [a_pad] = true, [b_pad] = true }), expected))
  end)
  if not ok then
    if moved_b then pcall(api.nvim_win_set_config, b, { win = b_pad, split = second[2] }) end
    if moved_a then pcall(api.nvim_win_set_config, a, { win = a_pad, split = first[2] }) end
  end
  for _, win in ipairs({ a_pad or 0, b_pad or 0 }) do
    if win ~= 0 and api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
  end
  pcall(vim.cmd, dimensions)
  if api.nvim_win_is_valid(a) then pcall(api.nvim_set_current_win, a) end
  vim.o.eventignore = ignore
  return ok and vim.deep_equal(vim.fn.winlayout(), expected)
end

return M
