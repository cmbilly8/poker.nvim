local cards = require("poker.cards")
local fs = require("poker.fs")

local ps = {}

local SUIT_MAP = {
  [0] = "c",
  [1] = "d",
  [2] = "h",
  [3] = "s",
}

local RANK_MAP = {
  [10] = "T",
  [11] = "J",
  [12] = "Q",
  [13] = "K",
  [14] = "A",
}

function ps.format_money(amount)
  amount = amount or 0
  return string.format("$%.2f", (amount or 0) / 100)
end

local function format_card(card)
  if not card then
    return "??"
  end
  local rank = RANK_MAP[card.rank] or tostring(card.rank or "?")
  local suit = SUIT_MAP[card.suit] or "?"
  return rank .. suit
end

local function format_board(board)
  if not board or #board == 0 then
    return "[]"
  end
  local labels = {}
  for _, card in ipairs(board) do
    labels[#labels + 1] = format_card(card)
  end
  return "[" .. table.concat(labels, " ") .. "]"
end

local function seat_sort(a, b)
  return (a.seat or 0) < (b.seat or 0)
end

local function action_lines(hand_state, street)
  local lines = {}
  for _, action in ipairs(hand_state.actions or {}) do
    if action.street == street then
      local name = action.player_name or string.format("P%d", action.player_id or 0)
      if action.action == "blind" then
        local label = (action.info and action.info.label) or "posts blind"
        lines[#lines + 1] = string.format("%s: %s %s", name, label, ps.format_money(action.amount or 0))
      elseif action.action == "fold" then
        lines[#lines + 1] = string.format("%s: folds", name)
      elseif action.action == "check" then
        lines[#lines + 1] = string.format("%s: checks", name)
      elseif action.action == "call" then
        lines[#lines + 1] = string.format("%s: calls %s", name, ps.format_money(action.amount or 0))
      elseif action.action == "bet" then
        lines[#lines + 1] = string.format("%s: bets %s", name, ps.format_money(action.amount or 0))
      elseif action.action == "raise" then
        if action.total then
          lines[#lines + 1] = string.format("%s: raises %s to %s", name, ps.format_money(action.amount or 0), ps.format_money(action.total or 0))
        else
          lines[#lines + 1] = string.format("%s: raises %s", name, ps.format_money(action.amount or 0))
        end
      end
    end
  end
  return lines
end

local function find_hero(players)
  for _, p in ipairs(players or {}) do
    if p.is_human then
      return p
    end
  end
  return players and players[1] or nil
end

local function players_by_seat(players)
  local copy = {}
  for _, p in ipairs(players or {}) do
    copy[#copy + 1] = p
  end
  table.sort(copy, seat_sort)
  return copy
end

local function winner_lookup(showdown)
  local map = {}
  for _, entry in ipairs(showdown and showdown.winners or {}) do
    if entry.player then
      map[entry.player.id or entry.player] = entry.amount or entry.payout or entry.player.stack_win or entry.share or entry.amount or 0
    elseif entry.player_id then
      map[entry.player_id] = entry.amount or 0
    end
  end
  return map
end

function ps.serialize_hand(hand_state)
  hand_state = hand_state or {}
  local config = hand_state.config or {}
  local players = players_by_seat(hand_state.players or hand_state.players_final or {})
  local hero = find_hero(players)
  local sb = config.small_blind or 0
  local bb = config.big_blind or 0
  local lines = {}
  lines[#lines + 1] = string.format("PokerStars Hand #%s:  Hold'em No Limit (%s/%s USD)", tostring(hand_state.id or ""), ps.format_money(sb), ps.format_money(bb))
  lines[#lines + 1] = string.format("Table '%s' %d-max Seat #%d is the button", config.table_name or "Poker.nvim", math.max(#players, 2), hand_state.button_index or 1)

  for _, p in ipairs(players) do
    lines[#lines + 1] = string.format("Seat %d: %s (%s in chips)", p.seat or 0, p.name or "Player", ps.format_money(p.stack_start or p.stack_end or config.starting_stack or 0))
  end

  lines[#lines + 1] = "*** HOLE CARDS ***"
  if hero and hero.hole_cards then
    lines[#lines + 1] = string.format("Dealt to %s [%s %s]", hero.name or "Hero", format_card(hero.hole_cards[1]), format_card(hero.hole_cards[2]))
  end

  for _, entry in ipairs(action_lines(hand_state, "preflop")) do
    lines[#lines + 1] = entry
  end

  if hand_state.board and #hand_state.board >= 3 then
    lines[#lines + 1] = string.format("*** FLOP *** %s", format_board({ hand_state.board[1], hand_state.board[2], hand_state.board[3] }))
    for _, entry in ipairs(action_lines(hand_state, "flop")) do
      lines[#lines + 1] = entry
    end
  end

  if hand_state.board and #hand_state.board >= 4 then
    lines[#lines + 1] = string.format("*** TURN *** %s", format_board({ hand_state.board[1], hand_state.board[2], hand_state.board[3], hand_state.board[4] }))
    for _, entry in ipairs(action_lines(hand_state, "turn")) do
      lines[#lines + 1] = entry
    end
  end

  if hand_state.board and #hand_state.board >= 5 then
    lines[#lines + 1] = string.format("*** RIVER *** %s", format_board(hand_state.board))
    for _, entry in ipairs(action_lines(hand_state, "river")) do
      lines[#lines + 1] = entry
    end
  end

  if hand_state.showdown then
    lines[#lines + 1] = "*** SHOW DOWN ***"
    local winnings = winner_lookup(hand_state.showdown)
    for _, p in ipairs(players) do
      local amount = winnings[p.id]
      if amount and amount > 0 then
        lines[#lines + 1] = string.format("%s: showed [%s %s] and won (%s)%s", p.name or "Player", format_card(p.hole_cards and p.hole_cards[1]), format_card(p.hole_cards and p.hole_cards[2]), ps.format_money(amount), hand_state.showdown.hand and (" with " .. hand_state.showdown.hand) or "")
      else
        lines[#lines + 1] = string.format("%s: showed [%s %s] and lost", p.name or "Player", format_card(p.hole_cards and p.hole_cards[1]), format_card(p.hole_cards and p.hole_cards[2]))
      end
    end
  end

  lines[#lines + 1] = "*** SUMMARY ***"
  lines[#lines + 1] = string.format("Total pot %s | Rake %s", ps.format_money(hand_state.pot or 0), ps.format_money(hand_state.rake or 0))
  lines[#lines + 1] = string.format("Board %s", format_board(hand_state.board or {}))
  if hand_state.showdown then
    local winnings = winner_lookup(hand_state.showdown)
    for _, p in ipairs(players) do
      local amount = winnings[p.id]
      if amount and amount > 0 then
        lines[#lines + 1] = string.format("Seat %d: %s showed [%s %s] and won (%s)", p.seat or 0, p.name or "Player", format_card(p.hole_cards and p.hole_cards[1]), format_card(p.hole_cards and p.hole_cards[2]), ps.format_money(amount))
      elseif p.folded then
        lines[#lines + 1] = string.format("Seat %d: %s folded", p.seat or 0, p.name or "Player")
      else
        lines[#lines + 1] = string.format("Seat %d: %s showed [%s %s] and lost", p.seat or 0, p.name or "Player", format_card(p.hole_cards and p.hole_cards[1]), format_card(p.hole_cards and p.hole_cards[2]))
      end
    end
  end

  return table.concat(lines, "\n")
end

function ps.write_hand(target_path, hand_text)
  if not target_path or not hand_text then
    return
  end
  fs.write_file(target_path, hand_text, "w")
end

ps.format_card = format_card
ps.format_board = format_board

return ps
