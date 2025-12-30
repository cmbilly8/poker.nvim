local match = require("poker.match")
local window = require("poker.window")
local utils = require("poker.utils")

local M = {}

local function current_player()
  local idx = match.current_player_index
  if not idx then
    return nil, nil
  end
  local player = match.players[idx]
  if not player then
    return nil, nil
  end
  return player, idx
end

local function open_table()
  match.start_session()
  match.start_hand()
  window.open_table()
  window.render()
end

local function destroy_table()
  window.destroy()
end

local function primary_action()
  if match.current_state == match.STATE.HAND_OVER then
    match.start_hand()
  else
    if match.current_state == match.STATE.AI_TURN then
      match.skip_to_player_turn()
    else
      local player = current_player()
      if player then
        local actions = match.available_actions(player)
        local chosen = nil
        if vim.tbl_contains(actions, "call") then
          chosen = "call"
        elseif vim.tbl_contains(actions, "check") then
          chosen = "check"
        else
          chosen = actions[1]
        end
        if chosen then
          match.player_action(chosen)
        end
      end
    end
  end
  window.render()
end

local function secondary_action()
  if match.current_state == match.STATE.AI_TURN then
    match.skip_to_player_turn()
  elseif match.current_state == match.STATE.HAND_OVER then
    match.start_hand()
  else
    match.player_action("fold")
  end
  window.render()
end

local function bet_action()
  if match.current_state ~= match.STATE.PLAYER_TURN then
    return
  end

  local player = current_player()
  if not player then
    return
  end

  local actions = match.available_actions(player)
  local can_bet = vim.tbl_contains(actions, "bet")
  local can_raise = vim.tbl_contains(actions, "raise")
  if not can_bet and not can_raise then
    vim.notify("No betting action available", vim.log.levels.INFO, { title = "Poker" })
    window.render()
    return
  end

  local state = match.get_state(player)
  local min_total
  if can_bet then
    min_total = state.min_raise or match.config.big_blind or 0
  else
    min_total = (state.current_bet or 0) + (state.min_raise or match.config.big_blind or 0)
  end

  local max_total = (player.bet_in_round or 0) + (player.stack or 0)
  if max_total <= (player.bet_in_round or 0) then
    window.render()
    return
  end

  if min_total < (player.bet_in_round or 0) + 1 then
    min_total = (player.bet_in_round or 0) + 1
  end
  if min_total > max_total then
    min_total = max_total
  end

  local default_total = math.min(max_total, min_total)
  local label = can_bet and "Bet" or "Raise"

  vim.ui.input({
    prompt = string.format("%s amount (min %d, max %d): ", label, min_total, max_total),
    default = tostring(default_total),
  }, function(input)
    if not input or input == "" then
      window.render()
      return
    end

    local value = tonumber(input)
    if not value then
      vim.notify("Enter a numeric amount", vim.log.levels.WARN, { title = "Poker" })
      window.render()
      return
    end

    if value < min_total then
      value = min_total
    end
    if value > max_total then
      value = max_total
    end

    match.player_action(can_bet and "bet" or "raise", value)
    window.render()
  end)
end

local function reset_scores()
  match.reset_scores()
  window.update_title()
  window.render()
end

local function stats_action()
  window.toggle_stats()
end

local function reset_stats()
  window.reset_stats()
  window.render()
end

function M.create_commands()
  vim.api.nvim_create_user_command("Poker", open_table, {})
  vim.api.nvim_create_user_command("PokerQuit", destroy_table, {})
  vim.api.nvim_create_user_command("PokerPrimary", primary_action, {})
  vim.api.nvim_create_user_command("PokerSecondary", secondary_action, {})
  vim.api.nvim_create_user_command("PokerBet", bet_action, {})
  vim.api.nvim_create_user_command("PokerStats", stats_action, {})
  vim.api.nvim_create_user_command("PokerResetStats", reset_stats, {})
  vim.api.nvim_create_user_command("PokerResetScores", reset_scores, {})
end

return M
