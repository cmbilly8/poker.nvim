if not package.path:find("lua/%?%.lua", 1, true) then
  package.path = "./lua/?.lua;./lua/?/init.lua;./lua/?/?.lua;" .. package.path
end

local M = {}

local DEFAULT_HANDS = 10000
local DEFAULT_PLAYERS = 7

local function usage()
  return table.concat({
    "Usage: lua lua/poker/sim_cli.lua [options]",
    "",
    "Options:",
    "  --hands <n>        Number of hands to simulate (default 10000).",
    "  --players <n>      Total players at the table (default 7).",
    "  --acpc-path <path> Write ACPC log to the given path (default simulator path).",
    "  --help             Show this help text.",
  }, "\n")
end

local function sanitize_positive_integer(value, label)
  local num = tonumber(value)
  if not num then
    return nil, string.format("Invalid %s: %s", label, tostring(value))
  end
  num = math.floor(num)
  if num < 1 then
    return nil, string.format("Invalid %s: %s", label, tostring(value))
  end
  return num
end

local function split_long_flag(token)
  local key, value = token:match("^%-%-([^=]+)=(.+)$")
  if key then
    return "--" .. key, value
  end
  return token, nil
end

function M.parse_args(args)
  args = args or {}
  local opts = {
    hands = DEFAULT_HANDS,
    players = DEFAULT_PLAYERS,
  }
  local idx = 1
  while idx <= #args do
    local token = args[idx]
    local flag, inline = split_long_flag(token)
    if flag == "--help" then
      opts.help = true
      idx = idx + 1
    elseif flag == "--hands" then
      local value = inline or args[idx + 1]
      if not value then
        return nil, "Missing value for --hands"
      end
      local parsed, err = sanitize_positive_integer(value, "hands")
      if not parsed then
        return nil, err
      end
      opts.hands = parsed
      idx = inline and (idx + 1) or (idx + 2)
    elseif flag == "--players" then
      local value = inline or args[idx + 1]
      if not value then
        return nil, "Missing value for --players"
      end
      local parsed, err = sanitize_positive_integer(value, "players")
      if not parsed then
        return nil, err
      end
      opts.players = parsed
      idx = inline and (idx + 1) or (idx + 2)
    elseif flag == "--acpc-path" then
      local value = inline or args[idx + 1]
      if not value or value == "" then
        return nil, "Missing value for --acpc-path"
      end
      opts.acpc_path = value
      idx = inline and (idx + 1) or (idx + 2)
    else
      return nil, string.format("Unknown argument: %s", token)
    end
  end
  return opts
end

function M.run(args)
  local opts, err = M.parse_args(args)
  if not opts then
    io.stderr:write(err .. "\n" .. usage() .. "\n")
    return false
  end
  if opts.help then
    print(usage())
    return true
  end
  if not _G.vim then
    local ok, helper = pcall(require, "tests.helpers.mock_vim")
    if ok and helper and helper.setup then
      helper.setup()
    end
  end
  local simulator = require("poker.simulator")
  local path = simulator.run(opts)
  print("ACPC log written to " .. tostring(path))
  return true
end

if ... ~= "poker.sim_cli" then
  if not M.run(arg or {}) then
    os.exit(1)
  end
end

return M
