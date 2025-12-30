local cards = require("poker.cards")
local evaluator = require("poker.hand_evaluator")
local ai = require("poker.ai")
local opponent_model = require("poker.ai.opponent_model")
local stats = require("poker.stats")
local fs = require("poker.fs")
local logging = require("poker.match.logging")
local persistence = require("poker.match.persistence")
local utils = require("poker.utils")

local M = {}
local ensure_stats_tracker
local write_scores
local read_scores
local init_hand_log
local record_action
local finalize_hand_log

local AI_NAMES = { "Michael", "Gob", "Buster", "Lindsay", "Tobias", "Lucille" }

local data_path = vim.fn.stdpath("data")
local default_scores_path = string.format("%s/pokerscores.json", data_path)
local SCORE_SCHEMA_VERSION = 1

M.config = {
  starting_stack = 1000,
  small_blind = 10,
  big_blind = 20,
  ai_opponents = 6,
  scores_path = nil,
  ai_think_ms = 1000,
  table_name = "Poker.nvim",
  enable_exports = false,
  export_acpc_path = nil,
  export_pokerstars_dir = nil,
  persist_scores = true,
}

M.stats = {
  hands_played = 0,
  player_wins = 0,
  player_losses = 0,
  player_ties = 0,
  tracker = stats.new_store(),
}
M.deck_rng = nil
M.ai_rng = nil
M.rng_seed = nil

M.STATE = {
  PLAYER_TURN = "PLAYER_TURN",
  AI_TURN = "AI_TURN",
  DEALING = "DEALING",
  SHOWDOWN = "SHOWDOWN",
  HAND_OVER = "HAND_OVER",
}

M.street_order = { "pre-flop", "flop", "turn", "river" }
local POSITION_SEQUENCE = { "BTN", "SB", "BB", "UTG", "MP", "CO" }

M.players = {}
M.button_index = 1
M.current_player_index = nil
M.current_state = M.STATE.HAND_OVER
M.current_street_index = 1

M.board = {}
M.deck = {}
M.pending_players = {}
M.last_events = {}
M.showdown = nil
M.pot = 0
M.current_bet = 0
M.min_raise = M.config.big_blind
M.small_blind_index = nil
M.big_blind_index = nil
M.awaiting_restart = false
M.pending_opponent_removals = {}
M.waiting_on_ai = false
M.ai_timer_token = 0
M.force_fast_forward = false
M.on_change = nil
M.on_hand_complete = nil
M.hand_id = 0
M.current_hand_log = nil
M.last_hand_log = nil
M.preflop_raise_count = 0
local function sanitize_positive_integer(value, min)
  local num = tonumber(value)
  if not num then
    return nil
  end
  num = math.floor(num)
  if num < (min or 1) then
    return nil
  end
  return num
end

local function sanitize_non_negative_integer(value)
  local num = tonumber(value)
  if not num then
    return nil
  end
  num = math.floor(num)
  if num < 0 then
    return nil
  end
  return num
end

local function normalize_seed(value)
  local num = tonumber(value)
  if not num then
    return nil
  end
  num = math.floor(num)
  if num < 0 then
    num = -num
  end
  if num == 0 then
    num = 1
  end
  return num
end

local function build_lcg(seed)
  local mod = 2147483647
  local mul = 1103515245
  local inc = 12345
  local state = seed % mod

  local function next_state()
    state = (mul * state + inc) % mod
    return state
  end

  local function next_int(upper)
    if not upper or upper <= 0 then
      return 1
    end
    return (next_state() % upper) + 1
  end

  local function next_float()
    return next_state() / mod
  end

  return next_int, next_float
end

local function sanitize_string(value)
  if type(value) ~= "string" then
    return nil
  end
  local trimmed = vim.trim(value)
  if trimmed == "" then
    return nil
  end
  return trimmed
end

local function find_seat(player)
  if not player then
    return nil
  end
  for idx, entry in ipairs(M.players or {}) do
    if entry.id == player.id then
      return idx
    end
  end
  return nil
end

do
  local persistence_api = persistence.setup({
    match = M,
    stats = stats,
    fs = fs,
    default_scores_path = default_scores_path,
    schema_version = SCORE_SCHEMA_VERSION,
  })
  ensure_stats_tracker = persistence_api.ensure_stats_tracker
  write_scores = persistence_api.write_scores
  read_scores = persistence_api.read_scores

  local logging_api = logging.setup({
    match = M,
    cards = cards,
    opponent_model = opponent_model,
    stats = stats,
    fs = fs,
    ensure_stats_tracker = ensure_stats_tracker,
    write_scores = write_scores,
    find_seat = find_seat,
  })
  init_hand_log = logging_api.init_hand_log
  record_action = logging_api.record_action
  finalize_hand_log = logging_api.finalize_hand_log
end

local function notify_change()
  if type(M.on_change) == "function" then
    pcall(M.on_change)
  end
end

local function push_event(message)
  M.last_events[#M.last_events + 1] = message
  if #M.last_events > 50 then
    table.remove(M.last_events, 1)
  end
end

local function init_players()
  M.players = {}
  M.button_index = 1

  M.players[1] = {
    id = 1,
    name = "You",
    is_human = true,
    stack = M.config.starting_stack,
    hole_cards = {},
    folded = false,
    last_action = nil,
    bet_in_round = 0,
    total_contribution = 0,
    all_in = false,
  }

  for i = 1, M.config.ai_opponents do
    local name = AI_NAMES[i] or string.format("AI %d", i)
    M.players[#M.players + 1] = {
      id = #M.players + 1,
      name = name,
      is_human = false,
      stack = M.config.starting_stack,
      hole_cards = {},
      folded = false,
      last_action = nil,
      bet_in_round = 0,
      total_contribution = 0,
      all_in = false,
    }
  end
end

local function reset_player_state(player)
  player.hole_cards = {}
  player.folded = false
  player.last_action = nil
  player.bet_in_round = 0
  player.total_contribution = 0
  player.all_in = player.stack <= 0
  player.raised_preflop = false
end

local function reset_players()
  for _, player in ipairs(M.players) do
    reset_player_state(player)
  end
end

local function apply_pending_removals()
  if not M.pending_opponent_removals or vim.tbl_isempty(M.pending_opponent_removals) then
    return
  end

  local survivors = {}
  local new_button_index = nil
  for idx, player in ipairs(M.players) do
    if not M.pending_opponent_removals[player.id] then
      survivors[#survivors + 1] = player
      if idx == M.button_index then
        new_button_index = #survivors
      end
    end
  end

  if #survivors == 0 then
    M.players = {}
    M.button_index = 1
  else
    M.players = survivors
    if not new_button_index then
      new_button_index = ((M.button_index - 1) % #survivors) + 1
    end
    M.button_index = new_button_index
  end

  M.pending_opponent_removals = {}
end

local function post_hand_cleanup()
  local removed = {}
  for _, player in ipairs(M.players) do
    local broke = (player.stack or 0) <= 0
    if broke then
      if player.is_human then
        M.awaiting_restart = true
      else
        M.pending_opponent_removals[player.id] = true
        removed[#removed + 1] = player.name or "Opponent"
      end
    end
  end

  if #removed > 0 then
    push_event(string.format("%s busted out", table.concat(removed, ", ")))
  end

  if M.awaiting_restart then
    push_event("You are out of chips! Press primary to restart with a fresh stack.")
  end
end

local function alive_player_count()
  local count = 0
  for _, player in ipairs(M.players) do
    if not player.folded then
      count = count + 1
    end
  end
  return count
end

local function next_live_index(start_index)
  local total = #M.players
  if total == 0 then
    return nil
  end
  local start = start_index or 0
  for step = 1, total do
    local idx = ((start + step - 1) % total) + 1
    local candidate = M.players[idx]
    if candidate and not candidate.folded and not candidate.all_in then
      return idx
    end
  end
  return nil
end

local function reset_pending_players(exclude_index)
  M.pending_players = {}
  for index, player in ipairs(M.players) do
    if not player.folded and not player.all_in then
      if not exclude_index or index ~= exclude_index then
        M.pending_players[index] = true
      end
    end
  end
end

local function pending_count()
  local total = 0
  for _, flag in pairs(M.pending_players or {}) do
    if flag then
      total = total + 1
    end
  end
  return total
end

local function mark_acted(index)
  if M.pending_players then
    M.pending_players[index] = nil
  end
end

local function next_pending_index(start_index)
  if not M.pending_players then
    return nil
  end
  local total = #M.players
  if total == 0 then
    return nil
  end
  local start = start_index or 0
  for step = 1, total do
    local idx = ((start + step - 1) % total) + 1
    if M.pending_players[idx] then
      return idx
    end
  end
  return nil
end

local function seat_after(index)
  local total = #M.players
  if total == 0 then
    return nil
  end
  local start = index or 0
  return ((start) % total) + 1
end

local function build_position_lookup()
  local positions = {}
  local total = #M.players
  if total == 0 then
    return positions
  end
  local idx = M.button_index
  if not idx or idx < 1 or idx > total then
    idx = 1
  end
  for step = 1, total do
    local player = M.players[idx]
    if player then
      local label = POSITION_SEQUENCE[step] or "MP"
      positions[player.id] = label
    end
    idx = seat_after(idx)
  end
  return positions
end

local function amount_to_call(player)
  local required = M.current_bet - (player.bet_in_round or 0)
  if required < 0 then
    required = 0
  end
  return required
end

local function commit_chips(player, amount)
  local commit = math.min(amount, player.stack)
  if commit <= 0 then
    return 0
  end
  player.stack = player.stack - commit
  player.bet_in_round = (player.bet_in_round or 0) + commit
  player.total_contribution = (player.total_contribution or 0) + commit
  M.pot = M.pot + commit
  if player.stack == 0 then
    player.all_in = true
  end
  return commit
end

local function start_new_betting_round(start_index)
  M.current_bet = 0
  M.min_raise = M.config.big_blind
  local clearing_preflop = (M.current_street_index or 1) > 1
  if clearing_preflop then
    M.preflop_raise_count = 0
  end
  for _, player in ipairs(M.players) do
    player.bet_in_round = 0
    if clearing_preflop then
      player.raised_preflop = false
    end
    if player and not player.folded then
      player.last_action = nil
    end
  end
  reset_pending_players(nil)
  M.current_player_index = next_pending_index(start_index or M.button_index)
end

local function post_blind(index, amount, label)
  if not index then
    return 0
  end
  local player = M.players[index]
  if not player or player.folded or player.all_in then
    return 0
  end
  local posted = math.min(amount, player.stack)
  if posted <= 0 then
    return 0
  end
  commit_chips(player, posted)
  player.last_action = string.format("%s %d", label, posted)
  push_event(string.format("%s %s %d", player.name, label, posted))
  record_action(player, "blind", posted, player.bet_in_round, { label = label })
  return posted
end

local function record_stats_for_winners(winners)
  M.stats.hands_played = M.stats.hands_played + 1

  local human_in_winners = false
  for _, winner in ipairs(winners) do
    if winner.player.is_human then
      human_in_winners = true
      break
    end
  end

  if human_in_winners and #winners == 1 then
    M.stats.player_wins = M.stats.player_wins + 1
  elseif human_in_winners then
    M.stats.player_ties = M.stats.player_ties + 1
  else
    M.stats.player_losses = M.stats.player_losses + 1
  end

  write_scores()
end

local function format_payout_message(player, amount)
  local name = player and player.name or "Player"
  local normalized = ""
  if type(name) == "string" then
    normalized = string.lower(name)
  end
  local verb = "wins"
  if player and player.is_human and normalized == "you" then
    verb = "win"
  end
  return string.format("%s %s %d chips", name, verb, amount or 0)
end

local function build_side_pots()
  local entries = {}
  for _, player in ipairs(M.players) do
    local contribution = math.max(player.total_contribution or 0, 0)
    if contribution > 0 then
      entries[#entries + 1] = {
        player = player,
        contribution = contribution,
        seat = find_seat(player) or 0,
      }
    end
  end
  table.sort(entries, function(a, b)
    if a.contribution == b.contribution then
      return a.seat < b.seat
    end
    return a.contribution < b.contribution
  end)

  local pots = {}
  local previous = 0
  while #entries > 0 do
    local level = entries[1].contribution
    local diff = level - previous
    if diff > 0 then
      local eligible = {}
      for _, entry in ipairs(entries) do
        eligible[#eligible + 1] = entry.player
      end
      table.sort(eligible, function(a, b)
        return (find_seat(a) or 0) < (find_seat(b) or 0)
      end)
      pots[#pots + 1] = {
        amount = diff * #entries,
        eligible = eligible,
      }
    end
    previous = level
    while #entries > 0 and entries[1].contribution == level do
      table.remove(entries, 1)
    end
  end
  return pots
end

local function determine_pot_winners(pot, contender_lookup)
  local winners = {}
  local best = nil
  for _, player in ipairs(pot.eligible or {}) do
    local contender = contender_lookup[player.id]
    if contender then
      if not best or evaluator.is_better(contender.score, best.score) then
        best = contender
        winners = { contender }
      elseif evaluator.are_equal(contender.score, best.score) then
        winners[#winners + 1] = contender
      end
    end
  end
  return winners
end

local function resolve_showdown()
  local contenders = {}
  for _, player in ipairs(M.players) do
    if not player.folded then
      local cards = {}
      for _, card in ipairs(player.hole_cards) do
        cards[#cards + 1] = card
      end
      for _, card in ipairs(M.board) do
        cards[#cards + 1] = card
      end
      contenders[#contenders + 1] = {
        player = player,
        score = evaluator.best_hand(cards),
      }
    end
  end

  local contender_lookup = {}
  for _, contender in ipairs(contenders) do
    contender_lookup[contender.player.id] = contender
  end

  table.sort(contenders, function(a, b)
    return evaluator.is_better(a.score, b.score)
  end)

  local winners = {}
  local best = contenders[1]
  for _, contender in ipairs(contenders) do
    local same = evaluator.are_equal(best.score, contender.score)
    if same then
      winners[#winners + 1] = contender
    else
      break
    end
  end

  record_stats_for_winners(winners)

  local winner_lookup = {}
  for _, entry in ipairs(winners) do
    winner_lookup[entry.player.id] = true
  end
  for _, player in ipairs(M.players) do
    local saw_showdown = not player.folded
    opponent_model.record_showdown(player.id, winner_lookup[player.id] or false, saw_showdown)
  end

  local payout_messages = {}
  local pot_before = M.pot
  local winnings = {}
  if M.pot > 0 then
    local pots = build_side_pots()
    for _, pot in ipairs(pots) do
      if pot.amount > 0 then
        local pot_winners = determine_pot_winners(pot, contender_lookup)
        if #pot_winners > 0 then
          local share = math.floor(pot.amount / #pot_winners)
          local remainder = pot.amount % #pot_winners
          for idx, entry in ipairs(pot_winners) do
            local payout = share + ((idx <= remainder) and 1 or 0)
            if payout > 0 then
              winnings[entry.player.id] = (winnings[entry.player.id] or 0) + payout
            end
          end
        end
      end
    end
    for _, contender in ipairs(contenders) do
      local amount = winnings[contender.player.id]
      if amount ~= nil then
        if amount > 0 then
          contender.player.stack = contender.player.stack + amount
          contender.player.last_action = string.format("won %d", amount)
        else
          contender.player.last_action = "won"
        end
        contender.amount = amount
      else
        contender.amount = 0
      end
    end
    for _, player in ipairs(M.players) do
      local amount = winnings[player.id]
      if amount ~= nil then
        payout_messages[#payout_messages + 1] = format_payout_message(player, amount)
      elseif winner_lookup[player.id] then
        player.last_action = "won"
      end
    end
  else
    for _, contender in ipairs(contenders) do
      contender.amount = 0
    end
  end
  M.pot = 0

  local messages = {}
  vim.list_extend(messages, payout_messages)
  for _, contender in ipairs(contenders) do
    local line = string.format(
      "%s - %s - %s",
      contender.player.name,
      utils.describe_hand(contender.score),
      utils.cards_to_string(contender.score.cards)
    )
    messages[#messages + 1] = line
  end

  local showdown_entries = {}
  if next(winnings) ~= nil then
    for _, player in ipairs(M.players) do
      local amount = winnings[player.id]
      if amount ~= nil then
        showdown_entries[#showdown_entries + 1] = {
          player = player,
          score = contender_lookup[player.id] and contender_lookup[player.id].score or nil,
          amount = amount,
        }
      end
    end
  else
    for _, entry in ipairs(winners) do
      showdown_entries[#showdown_entries + 1] = {
        player = entry.player,
        score = entry.score,
        amount = entry.amount or 0,
      }
    end
  end

  M.last_events = messages
  local hand_description = utils.describe_hand(best.score)
  local showdown_details = {
    winners = showdown_entries,
    hand = hand_description,
    payouts = payout_messages,
  }
  M.showdown = showdown_details
  M.current_state = M.STATE.HAND_OVER
  finalize_hand_log({
    pot = pot_before,
    showdown = showdown_details,
  })
  post_hand_cleanup()
end

local function everyone_else_folded()
  for _, player in ipairs(M.players) do
    if not player.folded then
      local pot_before = M.pot
      local payout = M.pot
      if payout > 0 then
        player.stack = player.stack + payout
        player.last_action = string.format("won %d", payout)
      end
      M.pot = 0
      M.stats.hands_played = M.stats.hands_played + 1
      if player.is_human then
        M.stats.player_wins = M.stats.player_wins + 1
        push_event(string.format("Everyone folded. You win %d chips.", payout))
      else
        M.stats.player_losses = M.stats.player_losses + 1
        push_event(string.format("%s wins %d chips (everyone else folded)", player.name, payout))
      end
      write_scores()
      M.showdown = {
        winners = { { player = player, score = nil } },
        hand = "All opponents folded",
        payouts = { format_payout_message(player, payout) },
      }
      for _, entry in ipairs(M.players) do
        opponent_model.record_showdown(entry.id, entry.id == player.id, not entry.folded)
      end
      M.current_state = M.STATE.HAND_OVER
      finalize_hand_log({
        pot = pot_before,
        showdown = {
          winners = { { player = player, score = nil, amount = payout } },
          hand = "All opponents folded",
          payouts = { format_payout_message(player, payout) },
        },
      })
      post_hand_cleanup()
      return true
    end
  end
  return false
end

local function advance_street()
  if alive_player_count() <= 1 then
    everyone_else_folded()
    return
  end

  while true do
    M.current_street_index = M.current_street_index + 1

    if M.current_street_index == 2 then
      local flop = {}
      for _ = 1, 3 do
        local card = cards.draw(M.deck)
        if card then
          flop[#flop + 1] = card
        end
      end
      M.board = flop
      push_event("Flop dealt")
      if M.current_hand_log then
        M.current_hand_log.board = cards.clone_many(M.board)
      end
    elseif M.current_street_index == 3 then
      local turn = cards.draw(M.deck)
      if turn then
        M.board[#M.board + 1] = turn
      end
      push_event("Turn dealt")
      if M.current_hand_log then
        M.current_hand_log.board = cards.clone_many(M.board)
      end
    elseif M.current_street_index == 4 then
      local river = cards.draw(M.deck)
      if river then
        M.board[#M.board + 1] = river
      end
      push_event("River dealt")
      if M.current_hand_log then
        M.current_hand_log.board = cards.clone_many(M.board)
      end
    else
      M.current_state = M.STATE.SHOWDOWN
      push_event("Reaching showdown")
      return
    end

    start_new_betting_round(M.button_index)

    if pending_count() == 0 then
      if M.current_street_index >= #M.street_order then
        M.current_state = M.STATE.SHOWDOWN
        push_event("Reaching showdown")
        return
      end
      -- All remaining players are all-in; continue to next street automatically.
    else
      M.current_state = M.STATE.DEALING
      return
    end
  end
end

local function apply_action(index, action, amount)
  local player = M.players[index]
  if not player or player.folded or player.all_in then
    return
  end

  local choice = type(action) == "string" and string.lower(action) or nil
  if not choice then
    return
  end

  local event_message = nil

  if choice == "fold" then
    player.folded = true
    player.last_action = "fold"
    mark_acted(index)
    event_message = string.format("%s folds", player.name)
    record_action(player, "fold", 0, player.bet_in_round)
  elseif choice == "check" then
    if amount_to_call(player) > 0 then
      return
    end
    player.last_action = "check"
    mark_acted(index)
    event_message = string.format("%s checks", player.name)
    record_action(player, "check", 0, player.bet_in_round)
  elseif choice == "call" then
    local to_call = amount_to_call(player)
    if to_call <= 0 then
      player.last_action = "check"
      mark_acted(index)
      event_message = string.format("%s checks", player.name)
      record_action(player, "check", 0, player.bet_in_round)
    else
      local committed = commit_chips(player, to_call)
      local suffix = player.all_in and " (all-in)" or ""
      player.last_action = string.format("call %d%s", committed, suffix)
      mark_acted(index)
      event_message = string.format("%s calls for %d%s", player.name, committed, suffix)
      record_action(player, "call", committed, player.bet_in_round)
    end
  elseif choice == "bet" or choice == "raise" then
    local current_bet = M.current_bet
    if current_bet == 0 and choice == "raise" then
      choice = "bet"
    elseif current_bet > 0 and choice == "bet" then
      choice = "raise"
    end

    local target_total = math.floor(tonumber(amount) or 0)
    if target_total < 0 then
      target_total = 0
    end

    local max_total = player.bet_in_round + player.stack
    local min_total

    if choice == "bet" then
      min_total = M.config.big_blind
      if max_total < min_total then
        min_total = max_total
      end
    else
      min_total = current_bet + M.min_raise
      if max_total < min_total then
        min_total = max_total
      end
    end

    if target_total < min_total then
      target_total = min_total
    end
    if target_total > max_total then
      target_total = max_total
    end

    if target_total <= player.bet_in_round then
      local to_call = amount_to_call(player)
      if to_call <= 0 then
        player.last_action = "check"
        mark_acted(index)
        event_message = string.format("%s checks", player.name)
      else
        local committed = commit_chips(player, to_call)
        local suffix = player.all_in and " (all-in)" or ""
        player.last_action = string.format("call %d%s", committed, suffix)
        mark_acted(index)
        event_message = string.format("%s calls for %d%s", player.name, committed, suffix)
      end
    else
      local before_total = player.bet_in_round
      local commit_diff = target_total - before_total
      if commit_diff > 0 then
        commit_chips(player, commit_diff)
      end

      local suffix = player.all_in and " (all-in)" or ""
      if choice == "bet" then
        player.last_action = string.format("bet %d%s", player.bet_in_round, suffix)
        event_message = string.format("%s bets %d%s", player.name, player.bet_in_round, suffix)
      else
        player.last_action = string.format("raise to %d%s", player.bet_in_round, suffix)
        event_message = string.format("%s raises to %d%s", player.name, player.bet_in_round, suffix)
      end

      local increase = player.bet_in_round - current_bet
      if increase > 0 then
        M.min_raise = math.max(M.config.big_blind, increase)
      end
      M.current_bet = math.max(M.current_bet, player.bet_in_round)

      if M.current_street_index == 1 then
        M.preflop_raise_count = (M.preflop_raise_count or 0) + 1
        player.raised_preflop = true
      end

      reset_pending_players(index)
      mark_acted(index)
      record_action(player, choice, commit_diff, player.bet_in_round)
    end
  else
    return
  end

  if event_message then
    push_event(event_message)
  end

  if alive_player_count() <= 1 then
    everyone_else_folded()
    return
  end

  if pending_count() == 0 then
    if M.current_street_index >= #M.street_order then
      M.current_state = M.STATE.SHOWDOWN
    else
      advance_street()
    end
    return
  end

  local next_index = next_pending_index(index)
  M.current_player_index = next_index
end

local function perform_ai_action(player, index)
  local state = M.get_state(player)
  local decision = ai.decide(player, state)
  local action = nil
  local amount = nil

  if type(decision) == "table" then
    action = decision.action or decision[1]
    amount = decision.amount or decision[2]
  else
    action = decision
  end

  local available = M.available_actions(player)
  local to_call = amount_to_call(player)
  if type(action) ~= "string" or not vim.tbl_contains(available, action) then
    action = to_call > 0 and "call" or "check"
    amount = nil
  elseif action == "fold" and to_call <= 0 and (player.stack or 0) > 0 and vim.tbl_contains(available, "check") then
    action = "check"
  end

  apply_action(index, action, amount)

  notify_change()

  if M.current_state == M.STATE.HAND_OVER then
    return false
  end

  if M.current_state == M.STATE.SHOWDOWN then
    resolve_showdown()
    notify_change()
    return false
  end

  M.current_state = M.STATE.DEALING
  return true
end

M.configure = function(opts)
  if not opts then
    return
  end
  local stack = sanitize_positive_integer(opts.starting_stack, 1)
  if stack then
    M.config.starting_stack = stack
  end
  local small = sanitize_positive_integer(opts.small_blind, 1)
  if small then
    M.config.small_blind = small
  end
  local big = sanitize_positive_integer(opts.big_blind, 1)
  if big then
    M.config.big_blind = big
    M.min_raise = M.config.big_blind
  end
  local opponents = sanitize_positive_integer(opts.ai_opponents, 1)
  if opponents then
    M.config.ai_opponents = opponents
  end
  local scores_path = sanitize_string(opts.scores_path)
  if scores_path then
    M.config.scores_path = scores_path
  end
  local delay = sanitize_non_negative_integer(opts.ai_think_ms)
  if delay then
    M.config.ai_think_ms = delay
  end
  if opts.enable_exports ~= nil then
    M.config.enable_exports = opts.enable_exports and true or false
  end
  if opts.persist_scores ~= nil then
    M.config.persist_scores = opts.persist_scores and true or false
  end
  if opts.export_acpc_path ~= nil then
    local path_value = sanitize_string(opts.export_acpc_path)
    if path_value then
      M.config.export_acpc_path = path_value
    end
  end
  if opts.export_pokerstars_dir ~= nil then
    local dir_value = sanitize_string(opts.export_pokerstars_dir)
    if dir_value then
      M.config.export_pokerstars_dir = dir_value
    end
  end
  local table_name = sanitize_string(opts.table_name)
  if table_name then
    M.config.table_name = table_name
  end
end

M.set_on_change = function(callback)
  if callback ~= nil and type(callback) ~= "function" then
    return
  end
  M.on_change = callback
end

M.set_on_hand_complete = function(callback)
  if callback ~= nil and type(callback) ~= "function" then
    return
  end
  M.on_hand_complete = callback
end

M.get_rng_state = function()
  return {
    deck_rng = M.deck_rng,
    ai_rng = M.ai_rng,
    seed = M.rng_seed,
  }
end

M.set_rng = function(deck_rng, ai_rng)
  local previous = M.get_rng_state()
  M.rng_seed = nil
  if type(deck_rng) == "function" then
    M.deck_rng = deck_rng
  else
    M.deck_rng = nil
  end
  if type(ai_rng) == "function" then
    M.ai_rng = ai_rng
    ai.set_rng(ai_rng)
  else
    M.ai_rng = nil
    ai.set_rng(nil)
  end
  return previous
end

M.set_seed = function(seed)
  local normalized = normalize_seed(seed)
  if not normalized then
    return M.set_rng(nil, nil)
  end
  local deck_rng, ai_rng = build_lcg(normalized)
  local previous = M.set_rng(deck_rng, ai_rng)
  M.rng_seed = normalized
  return previous
end

M.restore_rng = function(state)
  if type(state) ~= "table" then
    M.set_rng(nil, nil)
    return
  end
  M.set_rng(state.deck_rng, state.ai_rng)
  M.rng_seed = state.seed
end

M.start_session = function()
  read_scores()
  opponent_model.reset()
  init_players()
  ensure_stats_tracker()
  M.waiting_on_ai = false
  M.ai_timer_token = (M.ai_timer_token or 0) + 1
  M.force_fast_forward = false
  M.awaiting_restart = false
  M.pending_opponent_removals = {}
  M.last_events = {}
  push_event("Poker table ready")
  M.pot = 0
  M.current_bet = 0
  M.min_raise = M.config.big_blind
  M.current_street_index = 1
  M.current_player_index = nil
  M.board = {}
  M.current_state = M.STATE.HAND_OVER
  M.showdown = nil
  M.current_hand_log = nil
  M.last_hand_log = nil
  M.hand_id = 0
  M.preflop_raise_count = 0
end

local function deal_hole_cards()
  for _ = 1, 2 do
    for _, player in ipairs(M.players) do
      local card = cards.draw(M.deck)
      if card then
        player.hole_cards[#player.hole_cards + 1] = card
      end
    end
  end
end

M.start_hand = function()
  M.waiting_on_ai = false
  M.ai_timer_token = (M.ai_timer_token or 0) + 1
  M.force_fast_forward = false

  if M.awaiting_restart then
    M.awaiting_restart = false
    init_players()
    M.pending_opponent_removals = {}
  else
    apply_pending_removals()
  end

  reset_players()
  M.deck = cards.new_shuffled(M.deck_rng)
  deal_hole_cards()
  M.board = {}
  M.showdown = nil
  M.pot = 0
  M.current_bet = 0
  M.min_raise = M.config.big_blind
  M.current_street_index = 1
  M.preflop_raise_count = 0

  init_hand_log()

  push_event("New hand dealt")

  M.button_index = seat_after(M.button_index)
  M.small_blind_index = next_live_index(M.button_index) or seat_after(M.button_index)
  M.big_blind_index = next_live_index(M.small_blind_index) or seat_after(M.small_blind_index)

  post_blind(M.small_blind_index, M.config.small_blind, "posts small blind")
  post_blind(M.big_blind_index, M.config.big_blind, "posts big blind")

  M.current_bet = 0
  if M.small_blind_index then
    M.current_bet = math.max(M.current_bet, M.players[M.small_blind_index].bet_in_round or 0)
  end
  if M.big_blind_index then
    M.current_bet = math.max(M.current_bet, M.players[M.big_blind_index].bet_in_round or 0)
  end
  reset_pending_players(nil)
  M.current_player_index = next_pending_index(M.big_blind_index)
  if not M.current_player_index then
    M.current_player_index = next_pending_index(M.button_index)
  end

  M.current_state = M.STATE.DEALING

  M.progress()
end

M.progress = function()
  local function prepare_actor()
    while true do
      if M.current_state == M.STATE.HAND_OVER or M.current_state == M.STATE.SHOWDOWN then
        return nil, nil
      end

      if alive_player_count() <= 1 then
        everyone_else_folded()
        return nil, nil
      end

      if pending_count() == 0 then
        advance_street()
        if M.current_state == M.STATE.HAND_OVER or M.current_state == M.STATE.SHOWDOWN then
          return nil, nil
        end
        -- Re-evaluate after advancing the street.
      end

      local idx = M.current_player_index
      if not idx or not (M.pending_players and M.pending_players[idx]) then
        idx = next_pending_index(idx or M.button_index)
        M.current_player_index = idx
      end

      if idx then
        local player = M.players[idx]
        if player and not player.folded and not player.all_in then
          return player, idx
        end
        mark_acted(idx)
        M.current_player_index = next_pending_index(idx)
      else
        -- No pending players left; advance street on next loop.
        advance_street()
        if M.current_state == M.STATE.HAND_OVER or M.current_state == M.STATE.SHOWDOWN then
          return nil, nil
        end
      end
    end
  end

  while true do
    if M.current_state == M.STATE.HAND_OVER then
      return
    end

    if M.current_state == M.STATE.SHOWDOWN then
      resolve_showdown()
      return
    end

    local player, index = prepare_actor()
    if not player then
      if M.current_state == M.STATE.SHOWDOWN then
        resolve_showdown()
      end
      return
    end

    if player.is_human then
      M.current_state = M.STATE.PLAYER_TURN
      notify_change()
      return
    end

    if M.waiting_on_ai then
      return
    end

    M.current_state = M.STATE.AI_TURN

    local think_ms = math.max(0, math.floor(tonumber(M.config.ai_think_ms) or 0))
    if M.force_fast_forward then
      think_ms = 0
    end
    if think_ms > 0 and vim.defer_fn then
      M.waiting_on_ai = true
      local token = (M.ai_timer_token or 0) + 1
      M.ai_timer_token = token
      notify_change()
      vim.defer_fn(function()
        if token ~= M.ai_timer_token then
          return
        end
        M.waiting_on_ai = false
        local continue = perform_ai_action(player, index)
        if continue then
          M.progress()
        end
      end, think_ms)
      return
    end

    local continue = perform_ai_action(player, index)
    if not continue then
      return
    end
  end
end

M.player_action = function(action, amount)
  if M.current_state ~= M.STATE.PLAYER_TURN then
    return
  end

  local idx = M.current_player_index
  if not idx then
    return
  end

  local player = M.players[idx]
  if not player or not player.is_human then
    return
  end

  local chosen_action = action
  local chosen_amount = amount

  if type(chosen_action) == "table" then
    local spec = chosen_action
    chosen_action = spec.action or spec[1]
    chosen_amount = spec.amount or spec[2]
  end

  local to_call = amount_to_call(player)
  local available = M.available_actions(player)

  if chosen_action == nil then
    chosen_action = to_call > 0 and "call" or "check"
  end

  if type(chosen_action) ~= "string" then
    return
  end

  chosen_action = string.lower(chosen_action)

  if chosen_action == "check" and to_call > 0 then
    chosen_action = "call"
  elseif chosen_action == "call" and to_call <= 0 then
    chosen_action = "check"
  end

  if not vim.tbl_contains(available, chosen_action) then
    if chosen_action == "bet" and vim.tbl_contains(available, "raise") then
      chosen_action = "raise"
    elseif chosen_action == "raise" and vim.tbl_contains(available, "bet") then
      chosen_action = "bet"
    elseif chosen_action == "call" and vim.tbl_contains(available, "check") and to_call <= 0 then
      chosen_action = "check"
    else
      return
    end
  end

  apply_action(idx, chosen_action, chosen_amount)
  M.progress()
end

M.skip_to_player_turn = function()
  if M.current_state == M.STATE.PLAYER_TURN or M.current_state == M.STATE.HAND_OVER then
    return
  end
  M.force_fast_forward = true
  if M.waiting_on_ai then
    local token = (M.ai_timer_token or 0) + 1
    M.ai_timer_token = token
    M.waiting_on_ai = false
    local idx = M.current_player_index
    local player = idx and M.players[idx]
    if player and not player.is_human then
      perform_ai_action(player, idx)
    end
  end
  M.progress()
  M.force_fast_forward = false
end

M.get_players = function()
  local list = {}
  local positions = build_position_lookup()
  for _, player in ipairs(M.players) do
    local seat = find_seat(player)
    local copy = {
      id = player.id,
      name = player.name,
      is_human = player.is_human,
      stack = player.stack,
      folded = player.folded,
      last_action = player.last_action,
      bet_in_round = player.bet_in_round,
      total_contribution = player.total_contribution,
      all_in = player.all_in,
      hole_cards = cards.clone_many(player.hole_cards),
      seat = seat,
      position = positions[player.id],
    }
    list[#list + 1] = copy
  end
  return list
end

M.get_board = function()
  return cards.clone_many(M.board)
end

M.get_hole_cards = function(player_id)
  for _, player in ipairs(M.players) do
    if player.id == player_id then
      return cards.clone_many(player.hole_cards)
    end
  end
  return {}
end

M.get_my_cards = function()
  return M.get_hole_cards(1)
end

M.available_actions = function(player)
  if not player or player.folded or player.all_in then
    return {}
  end

  local actions = {}
  local to_call = amount_to_call(player)
  if to_call <= 0 then
    actions[#actions + 1] = "check"
  else
    actions[#actions + 1] = "call"
  end

  actions[#actions + 1] = "fold"

  local max_total = player.bet_in_round + player.stack
  if player.stack > 0 then
    if M.current_bet == 0 then
      actions[#actions + 1] = "bet"
    elseif max_total > M.current_bet then
      actions[#actions + 1] = "raise"
    end
  end

  return actions
end

M.get_state = function(requester)
  local to_call = 0
  if requester then
    to_call = amount_to_call(requester)
  end
  local players = M.get_players()
  local seat = nil
  local position = nil
  if requester then
    for _, entry in ipairs(players) do
      if entry.id == requester.id then
        seat = entry.seat
        position = entry.position
        break
      end
    end
  end
  return {
    street = M.street_order[M.current_street_index] or "pre-flop",
    board = M.get_board(),
    players = players,
    you = requester,
    actions = M.available_actions(requester),
    pot = M.pot,
    current_bet = M.current_bet,
    min_raise = M.min_raise,
    to_call = to_call,
    events = vim.deepcopy(M.last_events),
    seat = seat,
    position = position,
    big_blind = M.config.big_blind,
    small_blind = M.config.small_blind,
    preflop_raise_count = (M.current_street_index == 1) and (M.preflop_raise_count or 0) or 0,
    has_raised = (M.current_street_index == 1) and (requester and requester.raised_preflop or false) or false,
  }
end

M.reset_scores = function()
  M.stats.hands_played = 0
  M.stats.player_wins = 0
  M.stats.player_losses = 0
  M.stats.player_ties = 0
  M.stats.tracker = stats.new_store()
  write_scores()
end

M.reset_stats = function()
  M.stats.tracker = stats.new_store()
  write_scores()
end

M.get_player_stats = function(player_id)
  ensure_stats_tracker()
  return stats.get_player_stats(M.stats.tracker, player_id)
end

return M
