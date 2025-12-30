local tracker = {}

local streets = { "preflop", "flop", "turn", "river" }

local function empty_counts()
  return {
    preflop = { open = 0, call = 0, fold = 0, total = 0 },
    flop = { raise = 0, call = 0, fold = 0, total = 0 },
    turn = { raise = 0, call = 0, fold = 0, total = 0 },
    river = { raise = 0, call = 0, fold = 0, total = 0 },
  }
end

local counts = empty_counts()

function tracker.reset()
  counts = empty_counts()
end

local function safe_increment(bucket, key)
  if bucket and bucket[key] ~= nil then
    bucket[key] = bucket[key] + 1
    bucket.total = bucket.total + 1
  end
end

function tracker.record(street, action)
  if not street or not action then
    return
  end
  local target = counts[street]
  if not target then
    return
  end
  if street == "preflop" then
    if action == "r" then
      safe_increment(target, "open")
    elseif action == "c" then
      safe_increment(target, "call")
    elseif action == "f" then
      safe_increment(target, "fold")
    end
  else
    if action == "r" then
      safe_increment(target, "raise")
    elseif action == "c" then
      safe_increment(target, "call")
    elseif action == "f" then
      safe_increment(target, "fold")
    end
  end
end

function tracker.export()
  local out = {}
  for _, street in ipairs(streets) do
    local c = counts[street]
    out[street] = {
      open = c.open,
      call = c.call,
      fold = c.fold,
      raise = c.raise,
      total = c.total,
    }
  end
  return out
end

return tracker
