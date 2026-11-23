"""Run with Python 3 + msgpack from the repository root."""
import os
import subprocess

import msgpack


p = subprocess.Popen(
    ["nvim", "--headless", "--embed", "-u", "NONE", "-i", "NONE"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
)
reader = msgpack.Unpacker(raw=False)
sequence = 0
redraws = []


def rpc(method, args):
    global sequence
    sequence += 1
    p.stdin.write(msgpack.packb([0, sequence, method, args], use_bin_type=True))
    p.stdin.flush()
    while True:
        for reply in reader:
            if reply[0] == 2 and reply[1] == "redraw":
                redraws.extend(reply[2])
            if reply[0] == 1 and reply[1] == sequence:
                if reply[2]:
                    raise AssertionError(reply[2])
                return reply[3]
        chunk = os.read(p.stdout.fileno(), 65536)
        if not chunk:
            raise RuntimeError("Neovim exited")
        reader.feed(chunk)


def lua(code):
    return rpc("nvim_exec_lua", [code, []])


def tick():
    lua("vim.wait(40, function() return false end)")


def resize(width, height=32):
    rpc("nvim_ui_try_resize", [width, height])
    tick()


try:
    rpc("nvim_ui_attach", [99, 32, {"rgb": True, "ext_linegrid": True, "ext_multigrid": True}])
    lua("""
      vim.opt.runtimepath:prepend(vim.fn.getcwd())
      require("win_box").setup()
      vim.o.laststatus = 3
      vim.o.splitright = true
      vim.o.splitbelow = true
      _G.left = vim.api.nvim_get_current_win()
      vim.cmd.vnew()
      _G.right = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_width(left, 30)
      require("win_box.ratio").remember()
    """)
    tick()
    resize(121, 36)
    assert lua("return vim.o.columns") == 121
    assert lua("return vim.api.nvim_win_get_width(left)") == 37
    resize(99)
    assert lua("return vim.api.nvim_win_get_width(left)") == 30
    lua("vim.wo[left].winfixwidth = true; require('win_box.ratio').remember()")
    resize(151)
    assert lua("return vim.api.nvim_win_get_width(left)") == 30
    lua("""
      vim.wo[left].winfixwidth = false
      vim.api.nvim_set_current_win(left)
      vim.cmd.new()
      _G.bottom = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(left)
      require("win_box.ratio").remember()
    """)
    tick()
    # Mixed layouts should color both shared edges of the short active pane;
    # at least one floating grid also proves that multigrid saw the overlay.
    assert lua("""
      local ranges = require('win_box.boundary').segments(
        left, require('win_box.layout').windows(), true
      )
      return vim.iter(ranges):any(function(r) return r.axis == 'h' end)
        and vim.iter(ranges):any(function(r) return r.axis == 'v' end)
    """)
    assert any(event[0] == "win_float_pos" for event in redraws)
    # In a T split, each accent owns only the cells of one shared separator.
    # The global float border must not add a grid cell or paint the junction.
    def check_accents(vert, horiz, ambi, expected_vert, expected_horiz):
        redraws.clear()
        accents = lua("""
          vim.o.winborder = "single"
          vim.opt.fillchars:append({ vert = VERT, horiz = HORIZ })
          vim.o.ambiwidth = AMBI
          require("win_box.boundary").draw({ boundary = true, ignore_filetypes = {} })
          vim.cmd.redraw()
          local result = {}
          local box = require("win_box.layout").rect(left)
          for _, id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local conf = vim.api.nvim_win_get_config(id)
            if conf.zindex == 1 then
              assert(not (conf.row <= box.bottom and conf.row + conf.height > box.bottom
                and conf.col <= box.right and conf.col + conf.width > box.right), "covered T junction")
              result[#result + 1] = { id, conf.width, conf.height }
            end
          end
          return result
        """.replace("VERT", repr(vert)).replace("HORIZ", repr(horiz)).replace("AMBI", repr(ambi)))
        assert len(accents) == 2 and all(min(w, h) == 1 for _, w, h in accents), accents
        tick()
        grid_by_win, sizes, painted = {}, {}, {}
        for event in redraws:
            if event[0] == "win_float_pos":
                for values in event[1:]:
                    handle = values[1]
                    if isinstance(handle, msgpack.ExtType):
                        handle = msgpack.unpackb(handle.data)
                    grid_by_win[handle] = values[0]
            elif event[0] == "grid_resize":
                for grid, width, height in event[1:]:
                    sizes[grid] = (width, height)
            elif event[0] == "grid_line":
                for row in event[1:]:
                    painted.setdefault(row[0], set()).update(cell[0] for cell in row[3])
        for win, width, height in accents:
            grid = grid_by_win[win]
            assert sizes[grid] == (width, height), ("accent inherited frame", sizes[grid], width, height)
            glyph = expected_vert if width == 1 else expected_horiz
            assert glyph in painted[grid] and painted[grid] <= {glyph, " "}, painted[grid]

    check_accents("\u2502", "\u2500", "single", "\u2503", "\u2501")
    assert lua("return {vim.opt.fillchars:get().vert, vim.opt.fillchars:get().horiz}") == ["\u2502", "\u2500"]
    check_accents("|", "-", "double", "|", "-")
    lua("vim.o.ambiwidth = 'single'")
    resize(101)
    dims = lua("return {vim.api.nvim_win_get_width(left), vim.api.nvim_win_get_width(bottom)}")
    assert dims[0] == dims[1] and abs(dims[0] - 20) <= 1, dims

    lua("""
      _G.first_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd.tabnew()
      _G.tab2_left = vim.api.nvim_get_current_win()
      vim.cmd.vnew()
      vim.api.nvim_win_set_width(tab2_left, 60)
      require("win_box.ratio").remember()
    """)
    tick()
    resize(131)
    assert lua("return vim.api.nvim_win_get_width(tab2_left)") == 78
    lua("vim.api.nvim_set_current_tabpage(first_tab)")
    tick()
    assert abs(lua("return vim.api.nvim_win_get_width(left)") - 26) <= 1
    def horizontal_overlays():
        return lua("""
          local count = 0
          for _, id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local config = vim.api.nvim_win_get_config(id)
            if config.relative == "editor" and config.zindex == 1
              and config.height == 1 and config.width > 1 then
              assert(config.row == require('win_box.layout').rect(left).bottom)
              count = count + 1
            end
          end
          return count
        """)

    lua("""
      vim.api.nvim_set_current_win(left)
      vim.o.laststatus = 0
      vim.o.statusline = "%="
      vim.wo[left].winbar = "WINBOX_HUD_GUARD"
      require("win_box").setup()
    """)
    tick()
    assert horizontal_overlays() == 1
    assert lua("return vim.wo[left].winbar") == "WINBOX_HUD_GUARD"
    lua("""
      vim.wo[left].statusline = "WINBOX_STATUS_GUARD"
      require("win_box").setup()
    """)
    tick()
    assert horizontal_overlays() == 0
    def pick_style(style, labels, key):
        code = """
          local style, labels, key = STYLE, LABELS, KEY
          local wb = require("win_box")
          local layout = require("win_box.layout")
          local glyphs = require("win_box.glyphs")
          local expected_wins = layout.windows()
          vim.o.winborder = "double" -- must not change plain/large border policy
          wb.setup({ boundary = false, picker = { style = style },
            keys = { picker = { labels = labels } } })
          local getchar, open_win = vim.fn.getcharstr, vim.api.nvim_open_win
          local measured, hints, check_error = {}, {}
          vim.api.nvim_open_win = function(buf, enter, conf)
            local id = open_win(buf, enter, conf)
            if conf.zindex == 55 then hints[#hints + 1] = { id, conf.border } end
            return id
          end
          vim.fn.getcharstr = function()
            local ok, err = pcall(function()
              for index, hint in ipairs(hints) do
                local id, border = unpack(hint)
                local conf = vim.api.nvim_win_get_config(id)
                local label = labels:sub(index, index)
                local source = expected_wins[index]
                local area = layout.rect(source)
                local bar = style == "large" and vim.fn.getwininfo(source)[1].winbar or 0
                local top = math.min(area.top + bar, area.bottom - 1)
                local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(id), 0, -1, false)
                local expected, width, padding = { label }, 1, 0
                local big, big_width = glyphs.render(label)
                if style == "large" and big and area.right - area.left >= big_width + 2
                    and area.bottom - top >= #big + 2 then
                  expected, width, padding = big, big_width, 2
                end
                assert(vim.deep_equal(lines, expected), vim.inspect(lines))
                assert(conf.width == width and conf.height == #lines)
                assert(border == (padding > 0 and "single" or "none"))
                assert(conf.row == top + math.floor((area.bottom - top - conf.height - padding) / 2))
                assert(conf.col == area.left + math.floor((area.right - area.left - conf.width - padding) / 2))
                assert(conf.row + conf.height + padding <= area.bottom)
                assert(conf.col + conf.width + padding <= area.right)
                measured[index] = conf.height
              end
            end)
            if not ok then check_error = err end
            return key
          end
          local before = vim.api.nvim_get_current_win()
          local selected = wb.pick()
          vim.fn.getcharstr, vim.api.nvim_open_win = getchar, open_win
          assert(not check_error, check_error)
          for _, id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            assert(vim.api.nvim_win_get_config(id).zindex ~= 55, "picker overlay leaked")
          end
          if key == "a" then
            assert(selected == expected_wins[1])
          else
            assert(not selected and before == vim.api.nvim_get_current_win())
          end
          return measured
        """
        return lua(code.replace("STYLE", repr(style)).replace("LABELS", repr(labels)).replace("KEY", repr(key)))

    assert pick_style("plain", "as", "a") == [1, 1]
    assert pick_style("large", "a@", "a")[0] > 1
    assert pick_style("large", "a@", "a")[1] == 1
    assert any(event[0] == "grid_line" and any(
        any("▄" in cell[0] or "▀" in cell[0] for cell in row[3]) for row in event[1:]
    ) for event in redraws), "ANSI Compact cells did not reach the UI"
    assert any(event[0] == "grid_line" and any(
        any(cell[0] == "\u250c" for cell in row[3]) for row in event[1:]
    ) for event in redraws), "large hint frame did not reach the UI"
    # Leave enough space for the glyph alone, but not its complete frame.
    lua("""
      local glyph = require("win_box.glyphs").render("a")
      local bar = vim.fn.getwininfo(left)[1].winbar or 0
      vim.api.nvim_win_set_height(left, #glyph + bar + 1)
    """)
    assert pick_style("large", "as", "q")[0] == 1
    print("win-box multigrid: shared edges, ratio, HUD guard, framed ANSI Compact and fallback")
finally:
    p.terminate()
    p.wait(timeout=5)
