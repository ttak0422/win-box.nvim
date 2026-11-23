local layout = require("win_box.layout")
local M = {}
local snapshots = {}
local applying = false

local function build(raw)
  local kind, value = unpack(raw)
  if kind == "leaf" then
    return { win = value, width = vim.api.nvim_win_get_width(value), fixed = vim.wo[value].winfixwidth }
  end
  local children = vim.tbl_map(build, value)
  local row = kind == "row"
  local width = row and #children - 1 or 0
  local fixed = row
  for _, child in ipairs(children) do
    width = row and (width + child.width) or math.max(width, child.width)
    if row then
      fixed = fixed and child.fixed
    else
      fixed = fixed or child.fixed
    end
  end
  return { row = row, children = children, width = width, fixed = fixed }
end

local function distribute(node, width, result)
  if node.win then
    result[node.win] = { width = math.max(1, width) }
  elseif node.row then
    local target = width - (#node.children - 1)
    local weight = 0
    for _, child in ipairs(node.children) do
      if child.fixed then
        target = target - child.width
      else
        weight = weight + child.width
      end
    end
    local cumulative, previous = 0, 0
    for _, child in ipairs(node.children) do
      if child.fixed or weight == 0 then
        distribute(child, child.width, result)
      else
        cumulative = cumulative + child.width
        local rounded = math.floor(target * cumulative / weight + 0.5)
        distribute(child, rounded - previous, result)
        previous = rounded
      end
    end
  else
    for _, child in ipairs(node.children) do
      distribute(child, width, result)
    end
  end
end

function M.remember()
  if applying then
    return
  end
  local tab = vim.api.nvim_get_current_tabpage()
  local previous = snapshots[tab]
  if not previous or previous.columns == vim.o.columns then
    local raw = vim.fn.winlayout()
    snapshots[tab] = { columns = vim.o.columns, layout = raw, tree = build(raw) }
  end
  for handle in pairs(snapshots) do
    if not vim.api.nvim_tabpage_is_valid(handle) then
      snapshots[handle] = nil
    end
  end
end

function M.restore()
  if applying then
    return
  end
  local tab = vim.api.nvim_get_current_tabpage()
  local snapshot = snapshots[tab]
  if snapshot and snapshot.columns ~= vim.o.columns and vim.deep_equal(snapshot.layout, vim.fn.winlayout()) then
    applying = true
    local desired = {}
    distribute(snapshot.tree, snapshot.tree.width + vim.o.columns - snapshot.columns, desired)
    layout.restore_dimensions(desired, 1, false)
    applying = false
  end
  snapshots[tab] = nil
  M.remember()
end

return M
