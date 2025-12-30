local clamp = function(val, min, max)
  if val < min then
    return min
  end
  if val > max then
    return max
  end
  return val
end

local bounds = {
  open_raise_freq = { 0.05, 0.4 },
  call_freq = { 0.05, 0.3 },
  three_bet_value_freq = { 0.02, 0.2 },
  three_bet_bluff_freq = { 0.0, 0.15 },
  flop_fold_freq = { 0.05, 0.4 },
  flop_call_freq = { 0.3, 0.85 },
  flop_raise_freq = { 0.02, 0.2 },
  turn_fold_freq = { 0.05, 0.45 },
  turn_call_freq = { 0.25, 0.8 },
  turn_raise_freq = { 0.02, 0.2 },
  river_fold_freq = { 0.05, 0.5 },
  river_call_freq = { 0.25, 0.8 },
  river_raise_freq = { 0.02, 0.18 },
  bluff_ratio = { 0.2, 2.0 },
  probe_freq = { 0.05, 0.6 },
  learning_rate = { 0.001, 0.2 },
}

local function update_param(value, lr, error, min, max)
  return clamp(value - lr * error, min, max)
end

local function street_update(params, street_key, err_fold, err_raise, prefix)
  prefix = prefix or street_key
  params[prefix .. "_fold_freq"] = update_param(
    params[prefix .. "_fold_freq"],
    params.learning_rate,
    err_fold or 0,
    bounds[prefix .. "_fold_freq"][1],
    bounds[prefix .. "_fold_freq"][2]
  )
  params[prefix .. "_raise_freq"] = update_param(
    params[prefix .. "_raise_freq"],
    params.learning_rate,
    err_raise or 0,
    bounds[prefix .. "_raise_freq"][1],
    bounds[prefix .. "_raise_freq"][2]
  )
  local call_key = prefix .. "_call_freq"
  if params[call_key] then
    local err_call = -((err_fold or 0) + (err_raise or 0))
    params[call_key] = update_param(params[call_key], params.learning_rate, err_call, bounds[call_key][1], bounds[call_key][2])
  end
end

local M = {}

function M.update(observed, target)
  local params = require("poker.tuning_params")
  local errors = require("poker.frequency_error").compute(observed, target)

  params.open_raise_freq = update_param(
    params.open_raise_freq,
    params.learning_rate,
    (errors.preflop.open or 0),
    bounds.open_raise_freq[1],
    bounds.open_raise_freq[2]
  )
  params.call_freq = update_param(
    params.call_freq,
    params.learning_rate,
    (errors.preflop.call or 0),
    bounds.call_freq[1],
    bounds.call_freq[2]
  )

  params.three_bet_value_freq = update_param(
    params.three_bet_value_freq,
    params.learning_rate,
    (errors.preflop.open or 0),
    bounds.three_bet_value_freq[1],
    bounds.three_bet_value_freq[2]
  )
  params.three_bet_bluff_freq = update_param(
    params.three_bet_bluff_freq,
    params.learning_rate,
    (errors.preflop.call or 0),
    bounds.three_bet_bluff_freq[1],
    bounds.three_bet_bluff_freq[2]
  )

  street_update(params, "flop", errors.flop.fold, errors.flop.raise, "flop")
  street_update(params, "turn", errors.turn.fold, errors.turn.raise, "turn")
  street_update(params, "river", errors.river.fold, errors.river.raise, "river")

  return params
end

return M
