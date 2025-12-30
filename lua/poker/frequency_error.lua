local M = {}

local function compute_street(observed, target, keys)
  local out = {}
  local total = observed.total or 0
  if total <= 0 then
    return out
  end
  for _, key in ipairs(keys) do
    local obs = observed[key] or 0
    local tgt = (target and target[key]) or 0
    out[key] = (obs / total) - tgt
  end
  return out
end

function M.compute(observed, target)
  observed = observed or {}
  target = target or {}
  local err = {}
  err.preflop = compute_street(observed.preflop or {}, target.preflop, { "open", "call" })
  err.flop = compute_street(observed.flop or {}, target.flop, { "fold", "raise" })
  err.turn = compute_street(observed.turn or {}, target.turn, { "fold", "raise" })
  err.river = compute_street(observed.river or {}, target.river, { "fold", "raise" })
  return err
end

return M
