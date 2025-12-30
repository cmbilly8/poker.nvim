if not package.path:find("lua/%?%.lua", 1, true) then
  package.path = "./lua/?.lua;./lua/?/init.lua;./lua/?/?.lua;" .. package.path
end

local parser = require("poker.log_parser")
local json = require("poker.json")
local fs = require("poker.fs")

local path = arg and arg[1]
if not path then
  error("Usage: lua parse_log.lua <acpc_log_path>")
end

local observed = parser.parse_file(path)
local analysis = parser.normalize_counts(observed)

assert(fs.write_file("observed_freq.json", json.encode(observed), "w"), "cannot write observed_freq.json")
assert(fs.write_file("analysis.json", json.encode(analysis), "w"), "cannot write analysis.json")

print("observed frequencies written to observed_freq.json")
print("analysis written to analysis.json")
