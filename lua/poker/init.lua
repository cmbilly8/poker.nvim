local window = require("poker.window")
local utils = require("poker.utils")
local match = require("poker.match")

local M = {}

function M.setup(opts)
  opts = opts or {}

  if opts.suit_style ~= nil then
    utils.suit_style = opts.suit_style
  end

  if opts.keybindings ~= nil then
    M.set_keybindings(opts.keybindings)
  end

  match.configure(opts)
end

function M.set_keybindings(bindings)
  bindings = bindings or {}
  utils.apply_keybindings(bindings)
  if window.apply_keybindings then
    window.apply_keybindings()
  end
end

return M
