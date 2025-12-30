local M = {}

local function empty_counts()
  return {
    hands = 0,
    vpip = 0,
    pfr = 0,
    three_bet = 0,
    three_bet_opportunities = 0,
    cbet_opportunities = 0,
    fold_to_cbet = 0,
    aggression_bets = 0,
    aggression_raises = 0,
    aggression_calls = 0,
    saw_flop = 0,
    went_to_showdown = 0,
    won_showdown = 0,
    bb_defense = 0,
    bb_defense_opportunities = 0,
    faced_bet_flop = 0,
    fold_flop = 0,
    faced_bet_turn = 0,
    fold_turn = 0,
    faced_bet_river = 0,
    fold_river = 0,
  }
end

local function normalize_street(street)
  if not street then
    return "preflop"
  end
  if type(street) ~= "string" then
    return "preflop"
  end
  local name = street:lower()
  name = name:gsub("%W", "")
  if name == "" then
    return "preflop"
  end
  if name == "preflop" then
    return "preflop"
  end
  return name
end

local function ensure_store(store)
  if type(store) ~= "table" then
    store = {}
  end
  if type(store.players) ~= "table" then
    store.players = {}
  end
  return store
end

local function ensure_player(store, player_id)
  store = ensure_store(store)
  local entry = store.players[player_id]
  if type(entry) ~= "table" then
    entry = empty_counts()
    store.players[player_id] = entry
  else
    local defaults = empty_counts()
    for key, value in pairs(defaults) do
      if entry[key] == nil then
        entry[key] = value
      end
    end
  end
  return entry
end

local function safe_rate(numerator, denominator)
  if not denominator or denominator <= 0 then
    return nil
  end
  return numerator / denominator
end

local function aggression_factor(entry)
  local aggressive = (entry.aggression_bets or 0) + (entry.aggression_raises or 0)
  local calls = entry.aggression_calls or 0
  if calls == 0 then
    if aggressive == 0 then
      return 0
    end
    return math.huge
  end
  return aggressive / calls
end

function M.new_store()
  return { players = {} }
end

function M.ensure_store(store)
  return ensure_store(store)
end

function M.record_hand(store, log)
  if type(log) ~= "table" then
    return
  end
  store = ensure_store(store)
  local players = log.players or {}
  if #players == 0 then
    return
  end

  local alive = {}
  local folded_preflop = {}
  local preflop_first_action = {}
  local preflop_first_index = {}
  local preflop_raised = {}
  local vpip_this_hand = {}
  local pfr_this_hand = {}
  local three_bet_this_hand = {}
  local three_bet_opportunity = {}
  local preflop_raise_indices = {}
  local preflop_raise_count = 0
  local preflop_raiser_id = nil
  local big_blind_id = nil
  local faced_on_street = {}
  local hand_has_flop = (log.board and #log.board >= 3) or false

  for _, player in ipairs(players) do
    if player.id ~= nil then
      alive[player.id] = true
      faced_on_street[player.id] = { flop = false, turn = false, river = false }
      local entry = ensure_player(store, player.id)
      entry.hands = entry.hands + 1
    end
  end

  local street_state = {
    flop = { bet_seen = false, last_aggressor = nil },
    turn = { bet_seen = false, last_aggressor = nil },
    river = { bet_seen = false, last_aggressor = nil },
  }

  local cbet_active = false
  local cbet_faced = {}

  for idx, action in ipairs(log.actions or {}) do
    local pid = action.player_id
    local act = action.action
    if pid and act then
      local entry = ensure_player(store, pid)
      local street = normalize_street(action.street)
      if street == "flop" then
        hand_has_flop = true
      end

      if act == "blind" and action.info and action.info.label == "posts big blind" then
        big_blind_id = pid
      end

      if street == "preflop" then
        if act ~= "blind" and not preflop_first_index[pid] then
          preflop_first_index[pid] = idx
          preflop_first_action[pid] = act
        end

        if act ~= "blind" and preflop_raise_count > 0 and not preflop_raised[pid] and not three_bet_opportunity[pid] then
          entry.three_bet_opportunities = entry.three_bet_opportunities + 1
          three_bet_opportunity[pid] = true
        end

        if act == "fold" then
          folded_preflop[pid] = true
          alive[pid] = false
        elseif act == "call" then
          if not vpip_this_hand[pid] then
            entry.vpip = entry.vpip + 1
            vpip_this_hand[pid] = true
          end
        elseif act == "raise" or act == "bet" then
          if not vpip_this_hand[pid] then
            entry.vpip = entry.vpip + 1
            vpip_this_hand[pid] = true
          end
          if not preflop_raised[pid] then
            if preflop_raise_count == 0 then
              if not pfr_this_hand[pid] then
                entry.pfr = entry.pfr + 1
                pfr_this_hand[pid] = true
              end
            else
              if not three_bet_this_hand[pid] then
                entry.three_bet = entry.three_bet + 1
                three_bet_this_hand[pid] = true
              end
            end
            preflop_raised[pid] = true
          end
          preflop_raise_count = preflop_raise_count + 1
          preflop_raiser_id = pid
          preflop_raise_indices[#preflop_raise_indices + 1] = idx
        end
      else
        local state = street_state[street]
        if state then
          local faced = faced_on_street[pid]
          if state.bet_seen and state.last_aggressor ~= pid and faced and not faced[street] then
            entry["faced_bet_" .. street] = entry["faced_bet_" .. street] + 1
            faced[street] = true
            if act == "fold" then
              entry["fold_" .. street] = entry["fold_" .. street] + 1
            end
          end
          if act == "bet" or act == "raise" then
            state.bet_seen = true
            state.last_aggressor = pid
          end
        end

        if act == "fold" then
          alive[pid] = false
        elseif act == "bet" then
          entry.aggression_bets = entry.aggression_bets + 1
        elseif act == "raise" then
          entry.aggression_raises = entry.aggression_raises + 1
        elseif act == "call" then
          entry.aggression_calls = entry.aggression_calls + 1
        end

        if street == "flop" then
          if not cbet_active and act == "bet" and preflop_raiser_id and pid == preflop_raiser_id then
            cbet_active = true
            for other_id, is_alive in pairs(alive) do
              if is_alive and other_id ~= pid then
                local other_entry = ensure_player(store, other_id)
                other_entry.cbet_opportunities = other_entry.cbet_opportunities + 1
                cbet_faced[other_id] = true
              end
            end
          elseif cbet_active and cbet_faced[pid] then
            if act == "fold" then
              entry.fold_to_cbet = entry.fold_to_cbet + 1
            end
            cbet_faced[pid] = nil
          end
        end
      end
    end
  end

  if hand_has_flop then
    for _, player in ipairs(players) do
      local pid = player.id
      if pid ~= nil and not folded_preflop[pid] then
        local entry = ensure_player(store, pid)
        entry.saw_flop = entry.saw_flop + 1
      end
    end
  end

  local showdown = log.showdown
  local hand_showdown = showdown and showdown.hand and showdown.hand ~= "All opponents folded"
  if hand_showdown then
    local winners = {}
    for _, winner in ipairs(showdown.winners or {}) do
      local wid = winner.player and winner.player.id or winner.player_id
      if wid ~= nil then
        winners[wid] = true
      end
    end
    local finals = log.players_final or players
    for _, player in ipairs(finals) do
      local pid = player.id or player.player_id
      if pid ~= nil and not player.folded then
        local entry = ensure_player(store, pid)
        entry.went_to_showdown = entry.went_to_showdown + 1
        if winners[pid] then
          entry.won_showdown = entry.won_showdown + 1
        end
      end
    end
  end

  if big_blind_id and preflop_first_index[big_blind_id] then
    local faced_raise = false
    for _, raise_idx in ipairs(preflop_raise_indices) do
      if raise_idx < preflop_first_index[big_blind_id] then
        faced_raise = true
        break
      end
    end
    if faced_raise then
      local entry = ensure_player(store, big_blind_id)
      entry.bb_defense_opportunities = entry.bb_defense_opportunities + 1
      local action = preflop_first_action[big_blind_id]
      if action == "call" or action == "raise" then
        entry.bb_defense = entry.bb_defense + 1
      end
    end
  end
end

function M.get_player_stats(store, player_id)
  store = ensure_store(store)
  local entry = ensure_player(store, player_id or 0)
  return {
    vpip = safe_rate(entry.vpip, entry.hands),
    pfr = safe_rate(entry.pfr, entry.hands),
    three_bet = safe_rate(entry.three_bet, entry.three_bet_opportunities),
    fold_to_cbet = safe_rate(entry.fold_to_cbet, entry.cbet_opportunities),
    aggression_factor = aggression_factor(entry),
    wtsd = safe_rate(entry.went_to_showdown, entry.saw_flop),
    wsd = safe_rate(entry.won_showdown, entry.went_to_showdown),
    bb_defense = safe_rate(entry.bb_defense, entry.bb_defense_opportunities),
    fold_flop = safe_rate(entry.fold_flop, entry.faced_bet_flop),
    fold_turn = safe_rate(entry.fold_turn, entry.faced_bet_turn),
    fold_river = safe_rate(entry.fold_river, entry.faced_bet_river),
    counts = entry,
  }
end

return M
