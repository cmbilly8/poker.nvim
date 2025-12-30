local strategy = {}

local params = require("poker.tuning_params")

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function board_wetness(board)
  local suits = {}
  local ranks = {}
  for _, card in ipairs(board or {}) do
    suits[card.suit] = (suits[card.suit] or 0) + 1
    ranks[#ranks + 1] = card.rank or 0
  end
  table.sort(ranks)
  local wet = false
  for _, count in pairs(suits) do
    if count >= 3 then
      wet = true
      break
    end
  end
  if not wet and #ranks >= 3 then
    local spread = ranks[#ranks] - ranks[1]
    if spread <= 4 then
      wet = true
    end
  end
  return wet
end

function strategy.cbet_frequency(eval, bucket, board, player_count, is_preflop_raiser, equity_score)
  local wet = board_wetness(board)
  local base = wet and 0.3 or 0.7
  if not is_preflop_raiser then
    base = base * 0.6
  end
  base = base * (1 - 0.15 * math.max(player_count - 2, 0))
  if bucket == 1 or bucket == 2 then
    base = base + 0.1
  elseif bucket >= 5 then
    base = base - 0.1
  end
  if equity_score then
    base = base + (equity_score - 0.5) * 0.3
  end
  if base < 0 then
    base = 0
  end
  if base > 1 then
    base = 1
  end
  return base
end

function strategy.is_forced_blind_raise(action, betting_round, big_blind)
  if betting_round ~= 0 then
    return false
  end
  if type(action) ~= "string" then
    return false
  end
  local chip_amount = tonumber(action:sub(2))
  if not chip_amount or chip_amount <= 0 then
    return false
  end
  local bb = big_blind or 20
  return chip_amount <= bb
end

function strategy.mdf_required(to_call, pot)
  if not to_call or to_call <= 0 then
    return 0
  end
  pot = pot or 0
  local denom = pot + to_call
  if denom <= 0 then
    return 0
  end
  return clamp01(1 - (to_call / denom))
end

local function bucket_weight(bucket)
  if bucket == 3 then
    return 0.25
  elseif bucket == 4 then
    return 0.22
  elseif bucket == 5 then
    return 0.18
  elseif bucket <= 2 then
    return 0.12
  elseif bucket == 6 then
    return 0.1
  elseif bucket == 7 then
    return 0.08
  else
    return 0.05
  end
end

function strategy.compute_call_frequency(eval, bucket, equity, mdf_required)
  bucket = bucket or (eval and eval.bucket) or 5
  equity = equity or (eval and eval.equity) or 0
  assert(equity >= 0 and equity <= 1, "equity must be within [0,1]")
  local bw = bucket_weight(bucket)
  local call_prob = equity * 0.5 + bw
  call_prob = call_prob * (params.call_freq / 0.14)
  call_prob = math.max(call_prob, mdf_required or 0)
  return clamp01(call_prob)
end

local function normalize(dist)
  local total = (dist.fold or 0) + (dist.call or 0) + (dist.raise or 0)
  if total <= 0 then
    return { fold = 0, call = 0, raise = 0 }
  end
  return {
    fold = (dist.fold or 0) / total,
    call = (dist.call or 0) / total,
    raise = (dist.raise or 0) / total,
  }
end

local function shift(dist, from_key, to_key, amount)
  local available = math.min(dist[from_key] or 0, amount or 0)
  if available <= 0 then
    return
  end
  dist[from_key] = (dist[from_key] or 0) - available
  dist[to_key] = (dist[to_key] or 0) + available
end

function strategy.adjust_for_opponent(stats, decision_profile)
  stats = stats or {}
  local dist = {
    fold = decision_profile.fold or 0,
    call = decision_profile.call or 0,
    raise = decision_profile.raise or 0,
  }

  if (stats.fold_to_cbet or 0) > 0.55 then
    shift(dist, "fold", "raise", dist.fold * 0.2)
  end

  if (stats.fold_to_raise or stats.fold_to_cbet or 0) > 0.45 then
    shift(dist, "call", "raise", dist.call * 0.15)
  end

  if (stats.wtsd or 0) > 0.35 and (stats.fold_to_raise or 0.2) < 0.25 then
    shift(dist, "raise", "call", dist.raise * 0.15)
  end

  local aggression = stats.aggression_factor or stats.aggression or 0
  if aggression > 0.65 then
    shift(dist, "fold", "call", dist.fold * 0.3)
  end

  if stats.vpip ~= nil and (stats.vpip or 0) < 0.18 then
    shift(dist, "raise", "call", dist.raise * 0.2)
    shift(dist, "raise", "fold", dist.raise * 0.1)
  end

  return normalize(dist)
end

local function board_high_rank(board)
  local high = 0
  for _, card in ipairs(board or {}) do
    if card.rank and card.rank > high then
      high = card.rank
    end
  end
  return high
end

function strategy.oop_check_raise_probability(eval, bucket, equity, board)
  bucket = bucket or (eval and eval.bucket) or 8
  equity = equity or (eval and eval.equity) or 0
  local draw_bucket = bucket >= 7
  local combo_draw = (eval and eval.potential or 0) >= 0.12 and equity >= 0.3
  if not draw_bucket and not combo_draw then
    return 0
  end
  if equity < 0.3 then
    return 0
  end

  local wet = board_wetness(board)
  local prob = 0.08
  if wet then
    prob = prob + 0.05
  end
  if (eval and eval.fold_equity or 0) >= 0.35 then
    prob = prob + 0.05
  end
  if equity >= 0.45 then
    prob = prob + 0.04
  end
  if board_high_rank(board) <= 11 then
    prob = prob + 0.03
  end

  return math.min(prob, 0.25)
end

function strategy.oop_probe_turn(eval, bucket, equity, board)
  bucket = bucket or (eval and eval.bucket) or 5
  equity = equity or (eval and eval.equity) or 0
  local wet = board_wetness(board)
  local probe = 0

  if bucket >= 3 and bucket <= 6 then
    probe = (params.probe_freq or 0.2) * (0.5 + equity * 0.5)
  elseif bucket <= 2 then
    probe = 0.4 + (equity * 0.2)
  else
    probe = 0.05
  end

  if wet and bucket <= 4 then
    probe = probe + 0.05
  end

  probe = clamp01(probe)
  return { raise = probe, call = clamp01(1 - probe) }
end

function strategy.bluff_value_ratio(eval, bucket, equity, street)
  street = street or (eval and eval.street) or "flop"
  equity = equity or (eval and eval.equity) or 0
  bucket = bucket or (eval and eval.bucket) or 5

  local ratio = 1
  if street == "flop" then
    ratio = 2.0
  elseif street == "turn" then
    ratio = 1.0
  else
    ratio = 0.5
  end

  ratio = ratio * (params.bluff_ratio or 1.0)

  local class = "neutral"
  if bucket <= 2 or equity >= 0.7 then
    class = "value"
  elseif bucket == 7 or (eval and eval.potential or 0) >= 0.12 then
    class = "semi"
  elseif bucket >= 8 or equity < 0.25 then
    class = "air"
  end

  if class == "value" then
    return 1 + (street == "river" and 0.2 or 0.1)
  elseif class == "semi" then
    return clamp01(ratio * 0.9 + 0.2)
  else
    local multiplier = ratio * 0.6
    if street == "river" then
      multiplier = multiplier * 0.5
    end
    return multiplier
  end
end

local function clamp_amount(amount, min_total, max_total)
  if max_total > 0 and amount > max_total then
    amount = max_total
  end
  if amount < min_total then
    amount = min_total
  end
  return amount
end

function strategy.select_bet_size(street, bucket, reason, pot, to_call, min_raise, current_bet, stack)
  street = street or "flop"
  bucket = bucket or 4
  reason = reason or "value"
  pot = pot or 0
  to_call = to_call or 0
  min_raise = min_raise or 0
  current_bet = current_bet or 0
  stack = stack or (min_raise * 100)
  local opts = stack
  local rng = math.random
  local equity = 0
  local opponent = nil
  if type(stack) == "table" then
    opts = stack
    stack = opts.stack or (min_raise * 100)
    rng = opts.rng or math.random
    equity = opts.equity or 0
    opponent = opts.opponent
    if opts.stack then
      stack = opts.stack
    end
  end

  local strong = bucket <= 2 or reason == "value"
  local sizing = 0.5

  local function pick_from_distribution(distribution, deterministic)
    if deterministic then
      local best_size = nil
      local best_weight = -1
      for size, weight in pairs(distribution) do
        if weight > best_weight then
          best_weight = weight
          best_size = size
        end
      end
      return best_size
    end

    local total = 0
    for _, weight in pairs(distribution) do
      total = total + weight
    end
    if total <= 0 then
      return 0.5
    end
    local roll = rng()
    if roll > 1 then
      roll = roll - math.floor(roll)
    end
    local ordered = {}
    for size, _ in pairs(distribution) do
      ordered[#ordered + 1] = size
    end
    table.sort(ordered)
    local cursor = 0
    for _, size in ipairs(ordered) do
      local weight = distribution[size]
      cursor = cursor + weight / total
      if roll <= cursor then
        return size
      end
    end
    return ordered[#ordered]
  end

  if street == "preflop" then
    local base = min_raise > 0 and min_raise or (to_call > 0 and to_call or 20)
    local factors = strong and { 3.5, 4.5 } or { 2.5, 3.5 }
    local target = (to_call > 0) and (current_bet + to_call + base * factors[1]) or (base * factors[1])
    if strong and stack < target * 1.2 then
      target = stack
    end
    return clamp_amount(math.floor(target), current_bet + min_raise, current_bet + to_call + stack)
  else
    local dist = { [0.33] = 0.5, [0.5] = 0.3, [0.66] = 0.2 }
    if street == "turn" then
      dist = { [0.55] = 0.4, [0.7] = 0.35, [0.85] = 0.25 }
    elseif street == "river" then
      dist = { [0.5] = 0.25, [0.75] = 0.4, [1.0] = 0.35 }
    end

    if strong then
      dist[0.66] = (dist[0.66] or 0) + 0.1
      dist[0.75] = (dist[0.75] or 0) + 0.1
    elseif reason == "semibluff" or bucket >= 6 then
      dist[0.33] = (dist[0.33] or 0) + 0.15
      dist[0.5] = (dist[0.5] or 0) + 0.05
    end

    if opponent and (opponent.fold_to_raise or 0) > 0.5 then
      dist[0.33] = (dist[0.33] or 0) + 0.1
    elseif opponent and (opponent.vpip or 0) < 0.2 then
      dist[0.66] = (dist[0.66] or 0) + 0.1
    end

    if equity and equity >= 0.65 then
      dist[0.66] = (dist[0.66] or 0) + 0.05
    end

    sizing = pick_from_distribution(dist, type(opts) ~= "table")
  end

  local increase = math.max(min_raise, math.floor(pot * sizing))
  local target_total = current_bet + to_call + increase
  return clamp_amount(target_total, current_bet + min_raise, current_bet + to_call + stack)
end

return strategy
