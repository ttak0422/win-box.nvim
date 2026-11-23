local layout = require("win_box.layout")
local keys = require("win_box.keys")
local M = { style = "plain" }

function M.pick(focus, exclude)
  local hints, key_to_win = {}, {}
  local configured = keys.current.picker
  local labels = configured.labels
  local glyphs = M.style == "large" and require("win_box.glyphs")
  local i = 1
  local ok, result = pcall(function()
    for _, win in ipairs(layout.windows()) do
      if win ~= exclude and i <= #labels then
        local label = labels[i]
        i = i + 1
        local box = layout.rect(win)
        -- The native height includes the winbar; place large hints inside
        -- the text area whenever there is space.
        local top = box.top
        if glyphs then
          top = top + (vim.fn.getwininfo(win)[1].winbar or 0)
        end
        local lines, width, padding = { label }, 1, 0
        if glyphs then
          local bitmap, bitmap_width = glyphs.render(label)
          if bitmap and box.right - box.left >= bitmap_width + 2 and box.bottom - top >= #bitmap + 2 then
            lines, width, padding = bitmap, bitmap_width, 2
          end
        end
        top = math.min(top, box.bottom - 1)
        local height = #lines
        local buf = vim.api.nvim_create_buf(false, true)
        hints[#hints + 1] = buf
        vim.bo[buf].bufhidden = "wipe"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        local overlay = vim.api.nvim_open_win(buf, false, {
          relative = "editor",
          row = top + math.floor((box.bottom - top - height - padding) / 2),
          col = box.left + math.floor((box.right - box.left - width - padding) / 2),
          width = width,
          height = height,
          border = padding > 0 and "single" or "none",
          style = "minimal",
          noautocmd = true,
          focusable = false,
          mouse = false,
          zindex = 55,
        })
        vim.wo[overlay].winhighlight = "Normal:WinBoxPicker,NormalNC:WinBoxPicker,FloatBorder:WinBoxPicker"
        key_to_win[vim.fn.keytrans(label)] = win
      end
    end
    if next(key_to_win) then
      vim.cmd.redraw()
      local key = vim.fn.keytrans(vim.fn.getcharstr())
      if not configured.cancel[key] then return key_to_win[key] end
    end
  end)
  for _, buf in ipairs(hints) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  if ok and result and vim.api.nvim_win_is_valid(result) then
    if focus then
      vim.api.nvim_set_current_win(result)
    end
    return result
  end
end

return M
