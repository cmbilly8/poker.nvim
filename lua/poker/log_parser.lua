local tracker = require("poker.frequency_tracker")
local strategy = require("poker.ai.strategy")
local fs = require("poker.fs")

local M = {}

local streets = { "preflop", "flop", "turn", "river" }

local function detect_blind(line)
  if not line then
    return nil
  end
  local sb = line:match("blind ante %d+ (%d+)")
  local bb = line:match("blind ante %d+ %d+ (%d+)")
  local value = tonumber(bb or sb)
  if value and value > 0 then
    return value
  end
  return nil
end

local function process_segment(index, segment, blind_size)
  local street = streets[index] or "river"
  local i = 1
  while i <= #segment do
    local ch = segment:sub(i, i)
    if ch == "r" then
      local j = i + 1
      while j <= #segment and segment:sub(j, j):match("%d") do
        j = j + 1
      end
      local action = segment:sub(i, j - 1)
      if not strategy.is_forced_blind_raise(action, index - 1, blind_size) then
        tracker.record(street, "r")
      end
      i = j
    elseif ch == "c" then
      tracker.record(street, "c")
      i = i + 1
    elseif ch == "f" then
      tracker.record(street, "f")
      i = i + 1
    else
      i = i + 1
    end
  end
end

local function parse_lines_impl(lines, blind_size)
  tracker.reset()
  local detected_blind = blind_size
  for _, line in ipairs(lines or {}) do
    if not detected_blind then
      detected_blind = detect_blind(line)
    end
    if line:match("^STATE:") then
      local parts = {}
      for token in string.gmatch(line, "[^:]+") do
        parts[#parts + 1] = token
      end
      local history = parts[3] or ""
      local segments = {}
      for seg in string.gmatch(history .. "/", "([^/]*)/") do
        segments[#segments + 1] = seg
      end
      for idx, seg in ipairs(segments) do
        if seg ~= nil and seg ~= "" then
          process_segment(idx, seg, detected_blind)
        end
      end
    end
  end
  return tracker.export()
end

function M.parse_lines(lines, blind_size)
  return parse_lines_impl(lines or {}, blind_size)
end

function M.parse_file(path, blind_size)
  local file = assert(fs.open(path, "r"))
  local lines = {}
  for line in file:lines() do
    lines[#lines + 1] = line
  end
  file:close()
  return parse_lines_impl(lines, blind_size)
end

local function normalize_street(counts, mapping)
  local total = (counts and counts.total) or 0
  local normalized = { total = total }
  if total <= 0 then
    for _, key in ipairs(mapping) do
      normalized[key.output] = 0
    end
    return normalized
  end
  for _, key in ipairs(mapping) do
    normalized[key.output] = (counts[key.input] or 0) / total
  end
  return normalized
end

---Convert raw frequency counts into percentage analysis suitable for reports.
-- @param observed table result from parse_file/parse_lines
-- @return table per-street normalized frequencies with totals
function M.normalize_counts(observed)
  observed = observed or {}
  local out = {}
  out.preflop = normalize_street(observed.preflop or {}, {
    { input = "open", output = "open" },
    { input = "call", output = "call" },
    { input = "fold", output = "fold" },
  })
  for _, street in ipairs({ "flop", "turn", "river" }) do
    out[street] = normalize_street(observed[street] or {}, {
      { input = "raise", output = "raise" },
      { input = "call", output = "call" },
      { input = "fold", output = "fold" },
    })
  end
  return out
end

return M
