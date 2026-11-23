local M = {}

function M.windows(tab)
  local result = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative == "" and not config.external then
      result[#result + 1] = win
    end
  end
  return result
end

function M.rect(win)
  local p = vim.api.nvim_win_get_position(win)
  return {
    top = p[1],
    left = p[2],
    bottom = p[1] + vim.api.nvim_win_get_height(win),
    right = p[2] + vim.api.nvim_win_get_width(win),
  }
end

function M.snapshot(tab)
  local wins = M.windows(tab)
  local result = {}
  for _, win in ipairs(wins) do
    result[win] = {
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
    }
  end
  return result
end

function M.restore_dimensions(dimensions, sx, sy)
  -- Setting a size can affect neighboring windows. A second pass settles
  -- shared rows or columns without rebuilding or reopening any split.
  local axes = { { "width", sx or 1 } }
  if sy ~= false then
    axes[#axes + 1] = { "height", sy or 1 }
  end
  for _, axis in ipairs(axes) do
    local field, factor = unpack(axis)
    local get = vim.api["nvim_win_get_" .. field]
    local set = vim.api["nvim_win_set_" .. field]
    local fixed = "winfix" .. field
    for _ = 1, 2 do
      for _, win in ipairs(M.windows()) do
        local item = dimensions[win]
        if item and not vim.wo[win][fixed] and get(win) > math.max(1, math.floor(item[field] * factor + 0.5)) then
          pcall(set, win, math.max(1, math.floor(item[field] * factor + 0.5)))
        end
      end
      for _, win in ipairs(M.windows()) do
        local item = dimensions[win]
        if item and not vim.wo[win][fixed] and get(win) < math.max(1, math.floor(item[field] * factor + 0.5)) then
          pcall(set, win, math.max(1, math.floor(item[field] * factor + 0.5)))
        end
      end
    end
  end
end

return M
