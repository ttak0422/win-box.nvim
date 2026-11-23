local M = {}

local defaults = {
  adjust = {
    left = { "h", "<Left>" },
    down = { "j", "<Down>" },
    up = { "k", "<Up>" },
    right = { "l", "<Right>" },
    confirm = { "<CR>", "<NL>" },
    cancel = { "q", "<Esc>", "<C-C>" },
  },
  picker = {
    labels = "asdfghjklqwertyuiopzxcvbnm1234567890",
    cancel = { "<Esc>", "<C-C>" },
  },
}
local order = { "left", "down", "up", "right", "confirm", "cancel" }

local function field(values, fallback, name)
  if values[name] == nil then return fallback[name] end
  return values[name]
end

local function canonical(key, name)
  assert(type(key) == "string" and (vim.fn.strchars(key) == 1 or key:match("^<[^<>]+>$")),
    "win-box: keys." .. name .. " must contain single keys")
  local raw = vim.api.nvim_replace_termcodes(key, true, false, true)
  assert(raw ~= key or vim.fn.strchars(key) == 1, "win-box: unknown key " .. key)
  return vim.fn.keytrans(raw)
end

local function list(value, name)
  if value == false then return {} end
  if type(value) == "string" then value = { value } end
  assert(type(value) == "table" and vim.islist(value), "win-box: keys." .. name .. " must be a key, list, or false")
  local result = {}
  for _, key in ipairs(value) do
    result[#result + 1] = canonical(key, name)
  end
  return result
end

function M.compile(opts)
  opts = opts or {}
  assert(type(opts) == "table", "win-box: keys must be a table")
  local adjust, picker = opts.adjust or {}, opts.picker or {}
  assert(type(adjust) == "table" and type(picker) == "table", "win-box: keys.adjust and keys.picker must be tables")
  local result = { adjust = { bindings = {}, labels = {} }, picker = { labels = {}, cancel = {} } }
  for _, name in ipairs(order) do
    local values = list(field(adjust, defaults.adjust, name), "adjust." .. name)
    result.adjust.labels[name] = values
    for _, key in ipairs(values) do
      local old = result.adjust.bindings[key]
      assert(not old or old == name, "win-box: overlapping adjust key " .. key)
      result.adjust.bindings[key] = name
    end
  end
  assert(#result.adjust.labels.confirm + #result.adjust.labels.cancel > 0,
    "win-box: adjust requires at least one confirm or cancel key")

  local chars = field(picker, defaults.picker, "labels")
  if type(chars) == "string" then chars = vim.fn.split(chars, "\\zs") end
  if chars == false then chars = {} end
  assert(type(chars) == "table" and vim.islist(chars), "win-box: keys.picker.labels must be a string, list, or false")
  for _, key in ipairs(list(field(picker, defaults.picker, "cancel"), "picker.cancel")) do
    result.picker.cancel[key] = true
  end
  local seen = {}
  for _, label in ipairs(chars) do
    assert(type(label) == "string" and vim.fn.strchars(label) == 1
      and vim.fn.strdisplaywidth(label) == 1 and not label:match("^%s$"),
      "win-box: picker labels must be visible single-cell characters")
    local key = canonical(label, "picker.labels")
    assert(not seen[key] and not result.picker.cancel[key], "win-box: overlapping picker key " .. key)
    seen[key] = true
    result.picker.labels[#result.picker.labels + 1] = label
  end
  return result
end

M.current = M.compile()
return M
