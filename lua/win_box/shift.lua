local M = {}

-- Work with a copy of Neovim's split tree. The destination is a split
-- group/slot, not the screen coordinates of a neighboring window.
local function normalize(kind, children)
  local out = {}
  for _, child in ipairs(children) do
    if child[1] == kind then
      vim.list_extend(out, child[2])
    else
      out[#out + 1] = child
    end
  end
  return #out == 1 and out[1] or { kind, out }
end

local function path(node, win, ancestors)
  if node[1] == "leaf" then return node[2] == win end
  for i, child in ipairs(node[2]) do
    ancestors[#ancestors + 1] = { node = node, index = i }
    if path(child, win, ancestors) then return true end
    ancestors[#ancestors] = nil
  end
  return false
end

local function rewrite(tree, win, anchor, axis, first)
  local moving = { "leaf", win }
  local function visit(node)
    local result
    if node[1] == "leaf" then
      if node[2] == win then return nil end
      result = node
    else
      local children = {}
      for _, child in ipairs(node[2]) do
        children[#children + 1] = visit(child)
      end
      if #children > 0 then result = normalize(node[1], children) end
    end
    if result and node == anchor then
      if first then return normalize(axis, { moving, result }) end
      return normalize(axis, { result, moving })
    end
    return result
  end
  return visit(tree)
end

local function destination(tree, win, axis, first)
  local ancestors = {}
  if not path(tree, win, ancestors) or #ancestors == 0 then return end
  local p = ancestors[#ancestors]
  if p.node[1] ~= axis then
    return rewrite(tree, win, p.node, axis, first)
  end

  local siblings = p.node[2]
  local neighbor = siblings[p.index + (first and -1 or 1)]
  if not neighbor then
    local outer = ancestors[#ancestors - 1]
    return outer and rewrite(tree, win, outer.node, axis, first) or nil
  end
  if #siblings == 2 and neighbor[1] == "leaf" then
    return rewrite(tree, win, neighbor, axis, first)
  end
  return rewrite(tree, win, neighbor, axis == "row" and "col" or "row", true)
end

local function moves(tree, win, callback)
  local function probe(node, root)
    if node[1] ~= "leaf" and not root then
      for _, child in ipairs(node[2]) do if probe(child, false) then return true end end
      return false
    end
    if node[1] == "leaf" and node[2] == win then return false end
    local target = root and -1 or node[2]
    for _, axis in ipairs({ "row", "col" }) do
      for _, first in ipairs({ true, false }) do
        local split = axis == "row" and (first and "left" or "right") or (first and "above" or "below")
        local after = rewrite(tree, win, node, axis, first)
        if after and callback(after, { win = win, target = target, split = split }) then return true end
      end
    end
    if root then
      for _, child in ipairs(node[2]) do if probe(child, false) then return true end end
    end
    return false
  end
  return probe(tree, true)
end

local function single_move(tree, win, wanted)
  local winner
  moves(tree, win, function(after, op)
    if not vim.deep_equal(after, wanted) then return false end
    winner = op
    return true
  end)
  return winner
end

local function best_move(tree, ids, target, wanted)
  local winner = single_move(tree, target, wanted)
  if winner then return { winner } end
  if #ids > 12 then return nil end
  -- A true group edge has no leaf ID for the native API to address.
  -- Some such moves can be expressed as two native moves instead.
  local plan
  for _, id in ipairs(ids) do
    if moves(tree, id, function(middle, first)
      if vim.deep_equal(middle, tree) then return false end
      local seconds = id == target and ids or { target }
      for _, next_id in ipairs(seconds) do
        local second = single_move(middle, next_id, wanted)
        if second then
          local undo = single_move(middle, id, tree)
          if undo then
            plan = { first, second, middle = middle }
            return true
          end
        end
      end
      return false
    end) then return plan end
  end
end

function M.move(win, key, ids)
  local before = vim.fn.winlayout()
  local axis = (key == "h" or key == "l") and "row" or "col"
  local wanted = destination(before, win, axis, key == "h" or key == "k")
  if not wanted or vim.deep_equal(before, wanted) then return false end
  local ops = best_move(before, ids, win, wanted)
  if not ops then return false end
  local applied = 0
  local dims = vim.fn.winrestcmd()
  for _, op in ipairs(ops) do
    if not pcall(vim.api.nvim_win_set_config, op.win, { win = op.target, split = op.split }) then break end
    applied = applied + 1
  end
  if vim.deep_equal(vim.fn.winlayout(), wanted) then return true end
  -- In a constrained layout the native edit can fail. Reverse the first
  -- step when possible instead of silently substituting an exchange.
  for i = applied, 1, -1 do
    local target = i == 1 and before or ops.middle
    local current = vim.fn.winlayout()
    if not vim.deep_equal(current, target) then
      local undo = single_move(current, ops[i].win, target)
      if not undo then break end
      if not pcall(vim.api.nvim_win_set_config, undo.win, { win = undo.target, split = undo.split }) then break end
    end
  end
  if vim.deep_equal(vim.fn.winlayout(), before) then pcall(vim.cmd, dims) end
  return false
end

return M
