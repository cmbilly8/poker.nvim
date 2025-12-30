local model = {}

local stats_by_player = {}

local function ensure(player_id)
  if not stats_by_player[player_id] then
    stats_by_player[player_id] = {
      vpip = 0,
      pfr = 0,
      aggression = 0,
      aggression_factor = 0,
      fold_to_cbet = 0,
      fold_to_3bet = 0,
      fold_to_raise = 0,
      wtsd = 0,
      wsd = 0,
      w_money_sd = 0,
      hands = 0,
      saw_flop = 0,
      cbets = 0,
      folds_vs_cbet = 0,
      threetbets = 0,
      faced_3bet = 0,
      aggressive_actions = 0,
      faced_raises = 0,
      folds_vs_raise = 0,
      total_actions = 0,
      raises = 0,
      bets = 0,
      calls = 0,
      folds = 0,
    }
  end
  return stats_by_player[player_id]
end

function model.reset()
  for key in pairs(stats_by_player) do
    stats_by_player[key] = nil
  end
end

function model.record_action(player_id, action, amount, street)
  if not player_id then
    return
  end
  local s = ensure(player_id)
  s.total_actions = s.total_actions + 1
  if action == "bet" or action == "raise" then
    s.aggressive_actions = s.aggressive_actions + 1
    s.raises = s.raises + (action == "raise" and 1 or 0)
    s.bets = s.bets + (action == "bet" and 1 or 0)
    if street == "preflop" then
      s.pfr = s.pfr + 1
    end
  end
  if action == "call" then
    s.calls = s.calls + 1
  elseif action == "fold" then
    s.folds = s.folds + 1
  end
  if street == "preflop" and action ~= "fold" then
    s.vpip = s.vpip + 1
  end
  if street == "flop" then
    s.cbets = s.cbets + (action == "bet" and 1 or 0)
    s.folds_vs_cbet = s.folds_vs_cbet + (action == "fold" and 1 or 0)
  end
  if street == "preflop" then
    s.faced_3bet = s.faced_3bet + ((action == "call" or action == "fold") and 1 or 0)
    if action == "fold" then
      s.fold_to_3bet = s.fold_to_3bet + 1
    elseif action == "raise" then
      s.threetbets = s.threetbets + 1
    end
  elseif action == "fold" then
    s.faced_raises = s.faced_raises + 1
    s.folds_vs_raise = s.folds_vs_raise + 1
  elseif action == "call" then
    s.faced_raises = s.faced_raises + 1
  end
end

function model.record_showdown(player_id, won, saw_showdown)
  if not player_id then
    return
  end
  local s = ensure(player_id)
  s.hands = s.hands + 1
  if saw_showdown == nil then
    saw_showdown = true
  end
  if saw_showdown then
    s.wtsd = s.wtsd + 1
    if won then
      s.wsd = s.wsd + 1
      s.w_money_sd = s.w_money_sd + 1
    end
  end
end

function model.get_stats(player_id)
  local s = ensure(player_id or 0)
  local hands = math.max(s.hands, 1)
  local actions = math.max(s.total_actions, 1)
  local stats = {
    vpip = s.vpip / hands,
    pfr = s.pfr / hands,
    aggression = s.aggressive_actions / actions,
    aggression_factor = s.aggressive_actions / actions,
    fold_to_cbet = s.cbets > 0 and (s.folds_vs_cbet / s.cbets) or 0.3,
    fold_to_3bet = s.faced_3bet > 0 and (s.fold_to_3bet / s.faced_3bet) or 0.2,
    fold_to_raise = s.faced_raises > 0 and (s.folds_vs_raise / s.faced_raises) or 0.3,
    wtsd = s.wtsd / hands,
    wsd = s.wsd / math.max(s.wtsd, 1),
    ["w$sd"] = s.w_money_sd / math.max(s.wtsd, 1),
    actions = actions,
    folds = s.folds,
    raises = s.raises,
    bets = s.bets,
  }
  return stats
end

function model.opponent_aggression_factor(player_id)
  local s = ensure(player_id or 0)
  local actions = math.max(s.total_actions, 1)
  return (s.raises + s.bets) / actions
end

function model.opponent_fold_factor(player_id)
  local s = ensure(player_id or 0)
  local actions = math.max(s.total_actions, 1)
  return s.folds / actions
end

return model
