if not package.path:find("lua/%?%.lua", 1, true) then
  package.path = "./lua/?.lua;./lua/?/init.lua;./lua/?/?.lua;" .. package.path
end

local M = {}

local DEFAULT_ITERATIONS = 20
local DEFAULT_HANDS = 10000
local DEFAULT_PLAYERS = 7
local DEFAULT_ACPC_PATH = "tmp_acpc.log"

local function usage()
  return table.concat({
    "Usage: lua lua/poker/batch_cli.lua [options]",
    "",
    "Options:",
    "  --iterations <n>   Number of batch iterations (default 20).",
    "  --hands <n>        Hands per simulation run (default 10000).",
    "  --players <n>      Total players at the table (default 7).",
    "  --acpc-path <path> ACPC log path for each iteration (default tmp_acpc.log).",
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

local function is_executable(path)
  local cmd = string.format("[ -x %q ]", path)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local function ensure_mock_vim()
  if _G.vim then
    return
  end
  local ok, helper = pcall(require, "tests.helpers.mock_vim")
  if ok and helper and helper.setup then
    helper.setup()
  end
end

function M.parse_args(args)
  args = args or {}
  local opts = {
    iterations = DEFAULT_ITERATIONS,
    hands = DEFAULT_HANDS,
    players = DEFAULT_PLAYERS,
    acpc_path = DEFAULT_ACPC_PATH,
  }
  local idx = 1
  while idx <= #args do
    local token = args[idx]
    local flag, inline = split_long_flag(token)
    if flag == "--help" then
      opts.help = true
      idx = idx + 1
    elseif flag == "--iterations" then
      local value = inline or args[idx + 1]
      if not value then
        return nil, "Missing value for --iterations"
      end
      local parsed, err = sanitize_positive_integer(value, "iterations")
      if not parsed then
        return nil, err
      end
      opts.iterations = parsed
      idx = inline and (idx + 1) or (idx + 2)
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

  for iter = 1, opts.iterations do
    print(string.format("=== Iteration %d/%d ===", iter, opts.iterations))
    if is_executable("./acpc_match") then
      os.execute(string.format("./acpc_match > %q", opts.acpc_path))
    else
      ensure_mock_vim()
      local simulator = require("poker.simulator")
      simulator.run({ hands = opts.hands, players = opts.players, acpc_path = opts.acpc_path })
    end
    os.execute(string.format("lua lua/poker/parse_log.lua %q", opts.acpc_path))
    os.execute(string.format("TUNER_ITER=%d lua lua/poker/run_tuner.lua", iter))
    local snapshot = string.format("tuning_history/iter_%d.log", iter)
    os.execute(string.format("cp %q %q 2>/dev/null || true", opts.acpc_path, snapshot))
    print(string.format("Updated tuning parameters (iteration %d)", iter))
  end

  print("Batch tuning complete.")
  return true
end

if ... ~= "poker.batch_cli" then
  if not M.run(arg or {}) then
    os.exit(1)
  end
end

return M
