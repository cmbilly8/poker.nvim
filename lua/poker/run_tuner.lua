if not package.path:find("lua/%?%.lua", 1, true) then
  package.path = "./lua/?.lua;./lua/?/init.lua;./lua/?/?.lua;" .. package.path
end

local json = require("poker.json")
local auto_tune = require("poker.auto_tune")
local targets = require("poker.target_frequencies")
local fs = require("poker.fs")

local function read_observed()
  local content = fs.read_file("observed_freq.json")
  if not content then
    error("observed_freq.json not found; run parse_log.lua first")
  end
  return json.decode(content)
end

local function write_params(params)
  local f = fs.open("lua/poker/tuning_params.lua", "w")
  assert(f, "cannot write tuning_params.lua")
  f:write("return {\n")
  for k, v in pairs(params) do
    f:write(string.format("  %s = %.6f,\n", k, v))
  end
  f:write("}\n")
  f:close()
end

local function append_history(params, iter)
  fs.ensure_dir("tuning_history")
  local fname = string.format("tuning_history/iter_%04d.json", iter or 0)
  local f = fs.open(fname, "w")
  if not f then
    return
  end
  f:write(json.encode(params))
  f:close()
end

local observed = read_observed()
local params = auto_tune.update(observed, targets)

local iter = tonumber(os.getenv("TUNER_ITER") or "0")
write_params(params)
append_history(params, iter)

print("tuning params updated")
