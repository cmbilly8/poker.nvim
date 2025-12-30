local evaluator = require("poker.hand_evaluator")
local range_buckets = require("poker.ai.range_buckets")
local equity_mod = require("poker.ai.equity")
local opponent_model = require("poker.ai.opponent_model")
local strategy = require("poker.ai.strategy")
local tuning_params = require("poker.tuning_params")

local M = {}

local rng = math.random

---Swap the RNG used for sampling decisions.
--- @param fn fun():number
--- @return fun():number previous
function M.set_rng(fn)
  local previous = rng
  if type(fn) == "function" then
    rng = fn
  else
    rng = math.random
  end
  return previous
end

-- Static strength/draw parameters to keep the model readable and tunable.
local MODEL = {
  category_base = {
    [0] = 0.05, -- high card
    [1] = 0.4, -- one pair
    [2] = 0.6, -- two pair
    [3] = 0.7, -- trips
    [4] = 0.75, -- straight
    [5] = 0.8, -- flush
    [6] = 0.9, -- full house
    [7] = 0.96, -- quads
    [8] = 0.98, -- straight flush
  },
  pair_kicker_bonus = 0.15,
  hole_contribution = {
    [0] = -0.08, -- playing the board
    [1] = 0.0,
    [2] = 0.05,
  },
  draw = {
    straight = {
      flop = { open = 0.08, gut = 0.04 },
      turn = { open = 0.04, gut = 0.02 },
      river = { open = 0.0, gut = 0.0 },
    },
    flush = {
      flop = { four = 0.10, three = 0.04 },
      turn = { four = 0.05, three = 0.02 },
      river = { four = 0.0, three = 0.0 },
      nut_bonus = 0.02,
    },
  },
  weighting = {
    preflop = { made = 1.0, potential = 0.0 },
    flop = { made = 0.8, potential = 0.2 },
    turn = { made = 0.9, potential = 0.1 },
    river = { made = 1.0, potential = 0.0 },
  },
  pot_odds_margin = {
    preflop = 0.08,
    flop = 0.1,
    turn = 0.12,
    river = 0.15,
  },
}

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function contains(list, value)
  if not list then
    return false
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

local function normalize_dist(dist)
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

local function street_from_board(board)
  local count = board and #board or 0
  if count == 0 then
    return "preflop"
  elseif count == 3 then
    return "flop"
  elseif count == 4 then
    return "turn"
  elseif count >= 5 then
    return "river"
  end
  return "flop"
end

local function max_commit_total(player)
  local bet = (player and player.bet_in_round) or 0
  local stack = (player and player.stack) or 0
  return bet + stack
end

local function pick_villain_id(state, hero_id)
  for _, p in ipairs(state.players or {}) do
    if p.id and p.id ~= hero_id and not p.folded then
      return p.id
    end
  end
  return nil
end

local POSITION_BASE = {
  UTG = 0.13,
  MP = 0.18,
  CO = 0.25,
  BTN = 0.35,
  SB = 0.45,
  BB = 0.05,
}

local function state_position(state)
  if state and state.position then
    return string.upper(state.position)
  end
  if state and state.seat and state.players then
    local order = { "UTG", "MP", "CO", "BTN", "SB", "BB" }
    local idx = ((state.seat - 1) % #order) + 1
    return order[idx]
  end
  return "MP"
end

local function preflop_open_probability(bucket, position)
  local base = POSITION_BASE[position or "MP"] or POSITION_BASE.MP
  local bonus = {
    [1] = 0.4,
    [2] = 0.3,
    [3] = 0.2,
    [4] = 0.12,
    [5] = 0.08,
    [6] = 0.05,
  }
  local prob = base + (bonus[bucket or 5] or 0)
  if position == "SB" or position == "BTN" then
    prob = prob + 0.05
  elseif position == "UTG" then
    prob = prob - 0.02
  end
  prob = prob * (tuning_params.open_raise_freq / 0.18)
  return clamp01(prob)
end

local function bucket_is_value(bucket)
  return bucket and bucket <= 2
end

local function bucket_is_bluff_3bet(bucket)
  return bucket and bucket == 3
end

local function get_street_params(street)
  if street == "flop" then
    return {
      fold = tuning_params.flop_fold_freq,
      call = tuning_params.flop_call_freq,
      raise = tuning_params.flop_raise_freq,
    }
  elseif street == "turn" then
    return {
      fold = tuning_params.turn_fold_freq,
      call = tuning_params.turn_call_freq,
      raise = tuning_params.turn_raise_freq,
    }
  elseif street == "river" then
    return {
      fold = tuning_params.river_fold_freq,
      call = tuning_params.river_call_freq,
      raise = tuning_params.river_raise_freq,
    }
  end
  return { fold = 0.2, call = 0.6, raise = 0.2 }
end

local function preflop_strength(hole_cards, player_count)
  if not hole_cards or #hole_cards < 2 then
    return 0
  end
  local ranks = { hole_cards[1].rank or 0, hole_cards[2].rank or 0 }
  table.sort(ranks, function(a, b)
    return a > b
  end)
  local r1 = ranks[1]
  local r2 = ranks[2]
  local suited = hole_cards[1].suit ~= nil and hole_cards[1].suit == hole_cards[2].suit
  local gap = r1 - r2
  local base = 0.25

  if r1 == r2 then
    if r1 >= 14 then
      base = 0.98
    elseif r1 == 13 then
      base = 0.96
    elseif r1 == 12 then
      base = 0.94
    elseif r1 == 11 then
      base = 0.85
    elseif r1 == 10 then
      base = 0.82
    elseif r1 == 9 then
      base = 0.7
    elseif r1 == 8 then
      base = 0.65
    elseif r1 == 7 then
      base = 0.6
    elseif r1 >= 5 then
      base = 0.5
    else
      base = 0.4
    end
  elseif suited then
    if r1 == 14 and r2 == 13 then
      base = 0.92
    elseif r1 == 14 and r2 >= 12 then
      base = 0.82
    elseif r1 == 14 and r2 >= 11 then
      base = 0.8
    elseif r1 == 13 and r2 == 12 then
      base = 0.8
    elseif r1 >= 11 and r2 >= 10 then
      base = 0.68
    elseif gap == 1 and r1 >= 9 and r2 >= 5 then
      base = 0.62
    elseif gap == 1 and r1 >= 8 and r2 >= 4 then
      base = 0.6
    else
      base = 0.4
    end
  else
    if r1 == 14 and r2 == 13 then
      base = 0.82
    elseif r1 == 14 and r2 >= 11 then
      base = 0.72
    elseif r1 >= 13 and r2 >= 10 then
      base = 0.65
    elseif r1 >= 12 and r2 >= 11 then
      base = 0.62
    elseif r1 >= 10 and r2 >= 9 and gap <= 1 then
      base = 0.55
    elseif gap <= 2 and r1 >= 9 and r2 >= 7 then
      base = 0.32
    else
      base = 0.25
    end
  end

  local opponents = math.max((player_count or 2) - 1, 1)
  local penalty = 0.03 * math.max(opponents - 1, 0)
  return clamp01(base - penalty)
end

local function straight_draw_bonus(cards, street)
  local set = {}
  for _, card in ipairs(cards) do
    if card.rank then
      set[card.rank] = true
      if card.rank == 14 then
        set[1] = true
      end
    end
  end

  local open = false
  local gut = false
  for start = 1, 10 do
    local run = 0
    for offset = 0, 3 do
      if set[start + offset] then
        run = run + 1
      end
    end
    if run == 4 then
      open = true
      break
    end
  end

  if not open then
    for start = 1, 10 do
      local count = 0
      for offset = 0, 4 do
        if set[start + offset] then
          count = count + 1
        end
      end
      if count >= 4 then
        gut = true
        break
      end
    end
  end

  local street_cfg = MODEL.draw.straight[street or "flop"] or MODEL.draw.straight.flop
  if open then
    return street_cfg.open
  end
  if gut then
    return street_cfg.gut
  end
  return 0
end

local function flush_draw_bonus(cards, hole_cards, board, street, made_category)
  if made_category == 5 or made_category == 8 then
    return 0
  end

  local suit_counts = {}
  local highest_hole = {}
  local highest_board = {}
  for _, card in ipairs(cards) do
    if card.suit ~= nil then
      suit_counts[card.suit] = (suit_counts[card.suit] or 0) + 1
    end
  end
  for _, card in ipairs(hole_cards or {}) do
    if card.suit ~= nil then
      local current = highest_hole[card.suit] or 0
      if card.rank and card.rank > current then
        highest_hole[card.suit] = card.rank
      end
    end
  end
  for _, card in ipairs(board or {}) do
    if card.suit ~= nil then
      local current = highest_board[card.suit] or 0
      if card.rank and card.rank > current then
        highest_board[card.suit] = card.rank
      end
    end
  end

  local target_suit = nil
  local max_count = 0
  for suit, count in pairs(suit_counts) do
    if count > max_count then
      max_count = count
      target_suit = suit
    end
  end

  local street_cfg = MODEL.draw.flush[street or "flop"] or MODEL.draw.flush.flop
  local base = 0
  if max_count >= 4 then
    base = street_cfg.four
  elseif max_count == 3 then
    base = street_cfg.three
  end

  if base > 0 and target_suit ~= nil then
    local hole_high = highest_hole[target_suit] or 0
    local board_high = highest_board[target_suit] or 0
    if hole_high > board_high then
      base = base + MODEL.draw.flush.nut_bonus
    end
  end

  return base
end

local function count_hole_cards_used(hole_cards, board, target_score)
  if not target_score or not target_score.cards then
    return 0
  end
  local all = {}
  for _, card in ipairs(hole_cards or {}) do
    all[#all + 1] = card
  end
  for _, card in ipairs(board or {}) do
    all[#all + 1] = card
  end
  local total = #all
  if total < 5 then
    return 0
  end
  local indices = { 1, 2, 3, 4, 5 }
  local best = 0

  local function count_from_combo()
    local selection = {}
    local hole_used = 0
    for _, idx in ipairs(indices) do
      selection[#selection + 1] = all[idx]
      if idx <= #hole_cards then
        hole_used = hole_used + 1
      end
    end
    local score = evaluator.score_five(selection)
    if evaluator.are_equal(score, target_score) and hole_used > best then
      best = hole_used
    end
  end

  local function advance(pos)
    if pos == 0 then
      return false
    end
    if indices[pos] < total - (5 - pos) then
      indices[pos] = indices[pos] + 1
      for i = pos + 1, 5 do
        indices[i] = indices[i - 1] + 1
      end
      return true
    end
    return advance(pos - 1)
  end

  while true do
    count_from_combo()
    if not advance(5) then
      break
    end
  end

  return best
end

---Evaluate hand strength and draw potential.
--- @param player table
--- @param state table
--- @return table { total, made, potential, category, hole_card_contribution, street }
function M.evaluate_strength(player, state)
  player = player or {}
  state = state or {}
  local board = state.board or {}
  local street = street_from_board(board)
  local player_count = #(state.players or {})
  if player_count <= 0 then
    player_count = 2
  end

  if street == "preflop" then
    local made = preflop_strength(player.hole_cards, player_count)
    local bucket = range_buckets.preflop_bucket(player.hole_cards, state.position, player_count, state.seat)
    local eq = equity_mod.estimate({ total = made, potential = 0 }, bucket, player_count, state.board)
    assert(eq.equity >= 0 and eq.equity <= 1, "equity must be within [0,1]")
    return {
      total = made,
      made = made,
      potential = 0,
      category = nil,
      hole_card_contribution = 0,
      street = street,
      bucket = bucket,
      equity = eq.equity,
      fold_equity = eq.fold_equity,
    }
  end

  local combined = {}
  for _, card in ipairs(player.hole_cards or {}) do
    combined[#combined + 1] = card
  end
  for _, card in ipairs(board) do
    combined[#combined + 1] = card
  end

  local best = evaluator.best_hand(combined)
  local category = best and best.category or 0
  local made = MODEL.category_base[category] or 0
  if category == 1 and best and best.tiebreak and best.tiebreak[1] then
    local pair_rank = best.tiebreak[1]
    local kicker_bonus = ((pair_rank - 2) / 12) * MODEL.pair_kicker_bonus
    made = made + kicker_bonus
  elseif category == 2 and best and best.tiebreak and best.tiebreak[1] then
    made = made + 0.02 + math.min((best.tiebreak[1] - 8) / 6, 1) * 0.03
  elseif category >= 7 and best and best.tiebreak and best.tiebreak[1] then
    made = made + 0.01
  end

  local hole_used = count_hole_cards_used(player.hole_cards or {}, board, best)
  local hole_bonus = MODEL.hole_contribution[hole_used] or 0
  made = clamp01(made + hole_bonus)

  local potential = 0
  if street ~= "river" then
    potential = potential
      + flush_draw_bonus(combined, player.hole_cards, board, street, category)
      + straight_draw_bonus(combined, street)
  end

  local weights = MODEL.weighting[street] or MODEL.weighting.flop
  local total = clamp01((made * weights.made) + (potential * weights.potential))

  local bucket = range_buckets.postflop_bucket({ category = category, potential = potential, made = made, street = street, total = total }, board, player, state)
  local eq = equity_mod.estimate({ total = total, potential = potential }, bucket, player_count, board)
  assert(eq.equity >= 0 and eq.equity <= 1, "equity must be within [0,1]")

  return {
    total = total,
    made = made,
    potential = potential,
    category = category,
    hole_card_contribution = hole_bonus,
    street = street,
    bucket = bucket,
    equity = eq.equity,
    fold_equity = eq.fold_equity,
  }
end

local function pot_odds(to_call, pot)
  if to_call <= 0 then
    return 0
  end
  local denom = pot + to_call
  if denom <= 0 then
    return 1
  end
  return to_call / denom
end

local function target_raise(state, player, strength, street, reason, bucket, equity_score, opponent)
  street = street or "flop"
  local pot = (state and state.pot) or 0
  local to_call = (state and state.to_call) or 0
  local current = (state and state.current_bet) or 0
  local min_raise = (state and state.min_raise) or 0
  local stack = player and (player.stack or 0) or 0

  local target_total = strategy.select_bet_size(street, bucket, reason, pot, to_call, min_raise, current, {
    stack = stack,
    equity = equity_score,
    opponent = opponent,
    rng = rng,
  })

  local cap = max_commit_total(player)
  if cap > 0 and target_total > cap then
    target_total = cap
  end
  if target_total < current + min_raise then
    target_total = current + min_raise
  end
  return target_total
end

local function sample_action(dist, to_call, actions)
  local fold_weight = contains(actions, "fold") and (dist.fold or 0) or 0
  if to_call <= 0 then
    fold_weight = 0
  end
  local raise_action = contains(actions, "raise") and "raise" or (contains(actions, "bet") and "bet" or nil)
  local raise_weight = raise_action and (dist.raise or 0) or 0
  local call_action = nil
  if to_call > 0 then
    if contains(actions, "call") then
      call_action = "call"
    end
  else
    if contains(actions, "check") then
      call_action = "check"
    elseif contains(actions, "call") then
      call_action = "call"
    end
  end
  local call_weight = call_action and (dist.call or 0) or 0

  local total = fold_weight + raise_weight + call_weight
  if total <= 0 then
    return nil
  end

  local roll = rng()
  if roll > 1 then
    roll = roll - math.floor(roll)
  end
  local cursor = fold_weight / total
  if roll < cursor then
    return "fold"
  end
  cursor = cursor + call_weight / total
  if roll < cursor then
    return call_action
  end
  return raise_action
end

local function aggregate_opponent_stats(state, hero_id)
  local players = state.players or {}
  local total = { fold_to_cbet = 0, aggression = 0, count = 0 }
  for _, p in ipairs(players) do
    if p.id ~= hero_id then
      local s = opponent_model.get_stats(p.id)
      total.fold_to_cbet = total.fold_to_cbet + (s.fold_to_cbet or 0)
      total.aggression = total.aggression + (s.aggression or 0)
      total.count = total.count + 1
    end
  end
  if total.count == 0 then
    return { fold_to_cbet = 0.4, aggression = 0.4 }
  end
  return {
    fold_to_cbet = total.fold_to_cbet / total.count,
    aggression = total.aggression / total.count,
  }
end

--- Decide the action for an AI player using hand strength, draws, and probabilistic mixing.
--- @param player table the player taking the action
--- @param state table get of the table state (see `match.get_state`)
--- @return string|table|nil action A string action or { action = string, amount = number } for bets/raises.
function M.decide(player, state)
  state = state or {}
  player = player or {}
  local actions = state.actions or {}
  local to_call = state.to_call or 0
  local player_count = #(state.players or {})
  if player_count <= 0 then
    player_count = 2
  end

  local eval = M.evaluate_strength(player, state)
  local bucket = eval.bucket or 5
  local equity_score = eval.equity or eval.total or 0
  local made_score = eval.made or 0
  local fold_equity = eval.fold_equity or 0.3
  local odds = pot_odds(to_call, state.pot or 0)
  local margin = MODEL.pot_odds_margin[eval.street] or 0.1
  local multiway_tax = 0.03 * math.max(player_count - 2, 0)
  local villain_id = pick_villain_id(state, player.id)
  local opp = opponent_model.get_stats(villain_id)
  local multi_discount = 1 - 0.1 * math.max(player_count - 2, 0)

  local dist = { fold = 0, call = 0, raise = 0 }
  local raise_amount = nil
  local raise_reason = "default"
  local protect_preflop_bucket = false

  if eval.street == "preflop" then
    local position = state_position(state)
    local big_blind = state.big_blind or state.bigblind or 20
    local prior_raise = (state.current_bet or 0) > big_blind + 0.1
      or (state.preflop_raise_count and state.preflop_raise_count > 0)
      or (state.has_raised == true)
    protect_preflop_bucket = (not prior_raise) and (to_call <= big_blind) and (bucket and bucket <= 2)

    if not prior_raise then
      local open_prob = preflop_open_probability(bucket, position)
      local limp_prob = 0
      if to_call > 0 then
        if bucket >= 4 and bucket <= 6 then
          limp_prob = tuning_params.call_freq * 0.7
        elseif bucket == 3 or bucket == 7 then
          limp_prob = tuning_params.call_freq * 0.55
        end
      end
      dist.raise = open_prob
      dist.call = limp_prob * (tuning_params.call_freq / 0.14)
      dist.fold = 1 - (dist.raise + dist.call)
      if protect_preflop_bucket then
        dist.fold = 0
      elseif dist.fold < 0 then
        local total = dist.raise + dist.call
        dist.raise = dist.raise / total
        dist.call = dist.call / total
        dist.fold = 0
      end
      raise_reason = "open"
      if dist.fold < 0 then
        dist.fold = 0
      end
      if dist.raise > 0 then
        raise_amount = target_raise(state, player, eval.total, "preflop", raise_reason, bucket, equity_score, opp)
      end
    else
      local required = pot_odds(to_call, state.pot or 0)
      local raise_prob = 0
      local call_prob = 0
      if bucket_is_value(bucket) then
        raise_prob = tuning_params.three_bet_value_freq
      elseif bucket_is_bluff_3bet(bucket) then
        raise_prob = tuning_params.three_bet_bluff_freq
      end
      if (opp.vpip or 0) > 0.25 then
        raise_prob = raise_prob + 0.05
      end
      raise_prob = clamp01(raise_prob)
      if equity_score >= required then
        call_prob = tuning_params.call_freq
      elseif equity_score >= required * 0.9 then
        call_prob = tuning_params.call_freq * 0.6
      else
        call_prob = tuning_params.call_freq * 0.3
      end
      call_prob = math.max(call_prob, tuning_params.call_freq * 0.5)
      dist.raise = raise_prob
      dist.call = call_prob
      dist.fold = 1 - (dist.raise + dist.call)
      if dist.fold < 0 then
        dist.fold = 0
      end
      if dist.fold == 0 and dist.raise == 0 and dist.call == 0 then
        dist.fold = 1
      end
      raise_reason = "3bet"
      if dist.raise > 0 then
        raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
      end
    end
  elseif to_call > 0 then
    local required = odds + margin + multiway_tax
    local can_call = contains(actions, "call")
    local can_fold = contains(actions, "fold")
    local can_raise = contains(actions, "raise")
    local required_equity = 0
    if (state.pot or 0) + to_call > 0 then
      required_equity = to_call / ((state.pot or 0) + to_call)
    end

    local semi_bluff = can_raise and eval.potential >= 0.08 and made_score < 0.65 and bucket <= 3 and equity_score > 0.3
    local value_raise = can_raise and (bucket <= 2 or made_score >= 0.78 or eval.total >= 0.88 or equity_score >= 0.72)
    if player_count > 2 and value_raise then
      value_raise = equity_score >= required + 0.02
    end

    local street_params = get_street_params(eval.street)
    local mdf = strategy.mdf_required(to_call, state.pot or 0)
    local call_target = strategy.compute_call_frequency(eval, bucket, equity_score, mdf)
    if bucket >= 3 and bucket <= 5 then
      call_target = math.max(call_target, equity_score * 0.5)
    end

    if value_raise then
      local defense_target = math.max(call_target, mdf)
      local base_raise = street_params.raise or tuning_params.flop_raise_freq
      dist.raise = clamp01(base_raise + 0.25)
      if equity_score >= 0.85 or bucket <= 2 then
        dist.raise = clamp01(dist.raise + 0.15)
      end
      dist.call = math.max(street_params.call * 0.5, defense_target - dist.raise)
      dist.call = clamp01(dist.call)
      dist.fold = 1 - (dist.raise + dist.call)
      if dist.fold < 0 then
        local total = dist.raise + dist.call
        dist.raise = dist.raise / total
        dist.call = dist.call / total
        dist.fold = 0
      end
      raise_reason = "value"
      raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
    elseif semi_bluff then
      local freq = fold_equity * eval.potential * (1 - made_score)
      freq = freq * (1 + ((opp.fold_to_cbet or 0.5) - 0.5))
      freq = freq * multi_discount
      if bucket <= 2 then
        freq = math.max(freq, 0.35)
      elseif bucket == 3 then
        freq = math.max(freq, 0.25)
      end
      freq = clamp01(freq)
      dist.raise = freq
      raise_reason = "semibluff"
      raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
      if equity_score >= required and can_call then
        dist.call = math.max(call_target, 1 - dist.raise)
      elseif can_fold then
        dist.fold = 1 - dist.raise
      end
    elseif (eval.total >= required or equity_score >= required) and can_call then
      dist.call = math.max(call_target, 1 - dist.fold)
    elseif can_fold then
      dist.fold = 1
    end

    if equity_score < required_equity and can_fold then
      dist.fold = math.max(dist.fold, 0.5 + (required_equity - equity_score) * 0.5)
      dist.call = math.min(dist.call, 0.4)
      dist.raise = math.min(dist.raise, 0.2)
      local total_adj = dist.fold + dist.call + dist.raise
      if total_adj > 1 then
        dist.fold = dist.fold / total_adj
        dist.call = dist.call / total_adj
        dist.raise = dist.raise / total_adj
      end
    end

    if eval.street ~= "preflop" then
      if call_target < 0.6 then
        dist.fold = math.max(dist.fold, 0.15)
      end
      local need_fold_floor = equity_score < required_equity or ((equity_score < (required_equity + 0.2)) and bucket >= 5)
      if need_fold_floor then
        local floor = call_target > 0.6 and 0.15 or 0.3
        dist.fold = math.max(dist.fold, floor)
      end
    end

    local forced_fold = false
    if can_fold and equity_score < required and (eval.potential or 0) < 0.02 and bucket >= 5 then
      dist = { fold = 1, call = 0, raise = 0 }
      forced_fold = true
    end

    if equity_score < 0.2 and (eval.potential or 0) < 0.05 and not value_raise and not semi_bluff then
      dist.fold = 1
      dist.call = 0
      dist.raise = 0
      forced_fold = true
    end

    if not forced_fold then
      local defense = dist.call + dist.raise
      if defense < mdf then
        local need = mdf - defense
        local pull = math.min(dist.fold, need)
        dist.fold = dist.fold - pull
        dist.call = dist.call + pull
      end

      if not value_raise and dist.call < call_target then
        local gap = call_target - dist.call
        local shift = math.min(gap, dist.raise)
        dist.raise = dist.raise - shift
        dist.call = dist.call + shift
        if dist.call < call_target then
          local from_fold = math.min(call_target - dist.call, dist.fold)
          dist.fold = dist.fold - from_fold
          dist.call = dist.call + from_fold
        end
      end

      if contains(actions, "raise") then
        local cr_prob = strategy.oop_check_raise_probability(eval, bucket, equity_score, state.board or {})
        if cr_prob > 0 then
          dist.raise = dist.raise + cr_prob
          local reduce = cr_prob * 0.5
          dist.fold = math.max(0, dist.fold - reduce)
          dist.call = math.max(0, dist.call - reduce)
        end
      end
    end
  else
    local can_bet = contains(actions, "bet") or contains(actions, "raise")
    local can_check = contains(actions, "check")
    local value_hand = made_score >= 0.75 or eval.total >= 0.85 or bucket <= 2
    local semi_draw = eval.potential >= 0.12 and made_score < 0.7 and bucket <= 3
    local is_preflop_raiser = state.is_preflop_raiser or (state.preflop_raiser_id and state.preflop_raiser_id == player.id) or player.is_preflop_raiser

    if can_bet and value_hand then
      dist.raise = 0.6
      dist.call = can_check and 0.4 or 0.0
      raise_reason = "value"
      raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
    elseif can_bet and is_preflop_raiser then
      local freq = strategy.cbet_frequency(eval, bucket, state.board or {}, player_count, true, equity_score)
      freq = freq * (1 + (opp.fold_to_cbet - 0.5))
      if freq < 0 then
        freq = 0
      end
      if freq > 1 then
        freq = 1
      end
      dist.raise = freq
      dist.call = can_check and (1 - dist.raise) or 0.0
      raise_reason = "cbet"
      raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
    elseif can_bet and semi_draw then
      local freq = strategy.cbet_frequency(eval, bucket, state.board or {}, player_count, false, equity_score)
      freq = freq * (1 + (opp.fold_to_cbet - 0.5))
      freq = freq * multi_discount
      dist.raise = freq
      dist.call = can_check and (1 - dist.raise) or 0.0
      raise_reason = "semibluff"
      raise_amount = target_raise(state, player, eval.total, eval.street, raise_reason, bucket, equity_score, opp)
    elseif can_check then
      dist.call = 1
    end

    if eval.street == "turn" and can_bet and not is_preflop_raiser then
      local probe = strategy.oop_probe_turn(eval, bucket, equity_score, state.board or {})
      dist.raise = dist.raise + (probe.raise or 0)
      if can_check then
        dist.call = math.max(dist.call, probe.call or 0)
      end
    end
  end

  if eval.street ~= "preflop" then
    local required_strength = odds + margin + multiway_tax
    if dist.call > 0 and equity_score < required_strength then
      dist.fold = dist.fold + (dist.call * (0.5 + 0.5 * math.max(player_count - 2, 0) / math.max(player_count, 2)))
      dist.call = dist.call * 0.5
    end

    dist.fold = math.max(0, dist.fold)
    dist.call = math.max(0, dist.call)
    dist.raise = math.max(0, dist.raise)

    local fold_factor = opponent_model.opponent_fold_factor(villain_id)
    if fold_factor > 0.6 then
      dist.raise = dist.raise * 1.15
    elseif fold_factor < 0.2 then
      dist.raise = dist.raise * 0.8
    end

    local ratio_mult = strategy.bluff_value_ratio(eval, bucket, equity_score, eval.street)
    dist.raise = dist.raise * ratio_mult

    if not forced_fold then
      local base = {
        flop = { fold = 0.18, call = 0.72, raise = 0.10 },
        turn = { fold = 0.20, call = 0.69, raise = 0.11 },
        river = { fold = 0.22, call = 0.66, raise = 0.12 },
      }
      local target = {
        fold = tuning_params[eval.street .. "_fold_freq"],
        call = tuning_params[eval.street .. "_call_freq"],
        raise = tuning_params[eval.street .. "_raise_freq"],
      }
      local base_street = base[eval.street] or {}
      local function scale(val, key)
        local b = base_street[key] or val
        local t = target[key] or val
        if b <= 0 then
          return val
        end
        return val * (t / b)
      end
      dist.fold = scale(dist.fold, "fold")
      dist.call = scale(dist.call, "call")
      dist.raise = scale(dist.raise, "raise")
    end

    dist = strategy.adjust_for_opponent(opp, dist)
    dist = normalize_dist(dist)
  else
    if protect_preflop_bucket then
      dist.fold = 0
      dist.call = math.max(0, dist.call)
      dist.raise = math.max(0, dist.raise)
      dist = normalize_dist(dist)
    else
      dist = strategy.adjust_for_opponent(opp, dist)
      dist = normalize_dist(dist)
    end
  end

  local action = sample_action(dist, to_call, actions)
  if not action then
    if contains(actions, "check") then
      action = "check"
    elseif contains(actions, "call") then
      action = "call"
    elseif contains(actions, "fold") then
      action = "fold"
    else
      action = actions[1]
    end
  end

  if action == "fold" and to_call <= 0 and contains(actions, "check") then
    action = "check"
  end

  local normalized = action
  if normalized == "check" then
    normalized = "call"
  elseif normalized == "bet" then
    normalized = "raise"
  end

  assert(normalized == "fold" or normalized == "call" or normalized == "raise", "action must resolve to fold/call/raise")

  if action == "raise" or action == "bet" then
    local amount = raise_amount or target_raise(
      state,
      player,
      eval.total,
      eval.street,
      raise_reason,
      bucket,
      equity_score,
      opp
    )
    return { action = action, amount = amount }
  end
  return action
end

return M
