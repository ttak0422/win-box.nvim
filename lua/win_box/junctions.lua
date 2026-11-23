-- One digit per arm: left, right, up, down. 0 = absent, 1 = native
-- continuation (light), 2 = accent (heavy).
local shapes = {
  ["0101"] = "┌", ["0201"] = "┍", ["0102"] = "┎", ["0202"] = "┏",
  ["1001"] = "┐", ["2001"] = "┑", ["1002"] = "┒", ["2002"] = "┓",
  ["0110"] = "└", ["0210"] = "┕", ["0120"] = "┖", ["0220"] = "┗",
  ["1010"] = "┘", ["2010"] = "┙", ["1020"] = "┚", ["2020"] = "┛",
  ["0111"] = "├", ["0211"] = "┝", ["0121"] = "┞", ["0112"] = "┟",
  ["0122"] = "┠", ["0221"] = "┡", ["0212"] = "┢", ["0222"] = "┣",
  ["1011"] = "┤", ["2011"] = "┥", ["1021"] = "┦", ["1012"] = "┧",
  ["1022"] = "┨", ["2021"] = "┩", ["2012"] = "┪", ["2022"] = "┫",
  ["1101"] = "┬", ["2101"] = "┭", ["1201"] = "┮", ["2201"] = "┯",
  ["1102"] = "┰", ["2102"] = "┱", ["1202"] = "┲", ["2202"] = "┳",
  ["1110"] = "┴", ["2110"] = "┵", ["1210"] = "┶", ["2210"] = "┷",
  ["1120"] = "┸", ["2120"] = "┹", ["1220"] = "┺", ["2220"] = "┻",
  ["1111"] = "┼", ["2111"] = "┽", ["1211"] = "┾", ["2211"] = "┿",
  ["1121"] = "╀", ["1112"] = "╁", ["1122"] = "╂", ["2121"] = "╃",
  ["1221"] = "╄", ["2112"] = "╅", ["1212"] = "╆", ["2221"] = "╇",
  ["2212"] = "╈", ["2122"] = "╉", ["1222"] = "╊", ["2222"] = "╋",
}
local M = {}

local function arms(ranges, row, col)
  local result = { false, false, false, false }
  for _, range in ipairs(ranges) do
    local function contains(position)
      return range.start <= position and position < range.stop
    end
    if range.axis == "h" and range.cell == row then
      result[1] = result[1] or contains(col - 1)
      result[2] = result[2] or contains(col + 1)
    elseif range.axis == "v" and range.cell == col then
      result[3] = result[3] or contains(row - 1)
      result[4] = result[4] or contains(row + 1)
    end
  end
  return result
end

function M.cells(active, all, available)
  local cells, seen = {}, {}
  local function add(row, col)
    local point = row .. ":" .. col
    if seen[point] or not available(row, col) then return end
    seen[point] = true
    local near = arms(all, row, col)
    local accent = arms(active, row, col)
    if not (near[1] or near[2]) or not (near[3] or near[4]) then return end
    local weights = {}
    for i = 1, 4 do
      weights[i] = accent[i] and "2" or near[i] and "1" or "0"
    end
    local glyph = shapes[table.concat(weights)]
    if glyph then
      cells[#cells + 1] = {
        row = row,
        col = col,
        char = vim.fn.strdisplaywidth(glyph) == 1 and glyph or "+",
      }
    end
  end
  for _, range in ipairs(active) do
    if range.axis == "h" then
      add(range.cell, range.start - 1)
      add(range.cell, range.stop)
    else
      add(range.start - 1, range.cell)
      add(range.stop, range.cell)
    end
  end
  return cells
end

return M
