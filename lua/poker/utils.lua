local M = {}

M.keybindings = {
  primary = "j",
  secondary = "k",
  quit = "q",
  bet = "l",
  stats = ";",
}

M.suit_style = "black"

local SUITS_BLACK = {
  [0] = "♣",
  [1] = "♦",
  [2] = "♥",
  [3] = "♠",
}

local SUITS_WHITE = {
  [0] = "♧",
  [1] = "♢",
  [2] = "♡",
  [3] = "♤",
}

local RANK_LABELS = {
  [14] = "A",
  [13] = "K",
  [12] = "Q",
  [11] = "J",
  [10] = "10",
  [9] = "9",
  [8] = "8",
  [7] = "7",
  [6] = "6",
  [5] = "5",
  [4] = "4",
  [3] = "3",
  [2] = "2",
}

local HAND_NAMES = {
  [0] = "High Card",
  [1] = "One Pair",
  [2] = "Two Pair",
  [3] = "Three of a Kind",
  [4] = "Straight",
  [5] = "Flush",
  [6] = "Full House",
  [7] = "Four of a Kind",
  [8] = "Straight Flush",
}

function M.hand_name_from_category(category)
  if category == nil then
    return nil
  end
  return HAND_NAMES[category] or "Unknown"
end

function M.hand_name(score)
  if not score then
    return nil
  end
  if type(score) == "number" then
    return M.hand_name_from_category(score)
  end
  return M.hand_name_from_category(score.category)
end

function M.apply_keybindings(bindings)
  for key, value in pairs(bindings) do
    if key == "next" then
      M.keybindings.primary = value
    elseif key == "finish" then
      M.keybindings.secondary = value
    elseif key == "quit" then
      M.keybindings.quit = value
    elseif key == "primary" or key == "secondary" or key == "bet" then
      M.keybindings[key] = value
    elseif key == "stats" then
      M.keybindings.stats = value
    end
  end
end

function M.get_suit(card)
  local lookup = M.suit_style == "white" and SUITS_WHITE or SUITS_BLACK
  if not card.revealed then
    return "?"
  end
  return lookup[card.suit] or "?"
end

function M.rank_label(rank)
  return RANK_LABELS[rank] or tostring(rank)
end

local function join(values)
  return table.concat(values, " ")
end

local function describe_high_card(score)
  local labels = {}
  for i = 1, math.min(5, #score.tiebreak) do
    labels[#labels + 1] = M.rank_label(score.tiebreak[i])
  end
  return string.format("%s (%s)", HAND_NAMES[score.category], join(labels))
end

function M.describe_hand(score)
  if not score or not score.category then
    return "No Hand"
  end

  local name = HAND_NAMES[score.category] or "Unknown"

  if score.category == 8 then
    return string.format("%s (%s high)", name, M.rank_label(score.tiebreak[1]))
  elseif score.category == 7 then
    return string.format("%s (%s with %s kicker)", name, M.rank_label(score.tiebreak[1]), M.rank_label(score.tiebreak[2]))
  elseif score.category == 6 then
    return string.format("%s (%s full of %s)", name, M.rank_label(score.tiebreak[1]), M.rank_label(score.tiebreak[2]))
  elseif score.category == 5 then
    return describe_high_card(score)
  elseif score.category == 4 then
    return string.format("%s (%s high)", name, M.rank_label(score.tiebreak[1]))
  elseif score.category == 3 then
    return string.format("%s (%s with kickers %s %s)", name, M.rank_label(score.tiebreak[1]), M.rank_label(score.tiebreak[2]), M.rank_label(score.tiebreak[3]))
  elseif score.category == 2 then
    return string.format(
      "%s (%s and %s with %s kicker)",
      name,
      M.rank_label(score.tiebreak[1]),
      M.rank_label(score.tiebreak[2]),
      M.rank_label(score.tiebreak[3])
    )
  elseif score.category == 1 then
    return string.format(
      "%s (%s with kickers %s %s %s)",
      name,
      M.rank_label(score.tiebreak[1]),
      M.rank_label(score.tiebreak[2]),
      M.rank_label(score.tiebreak[3]),
      M.rank_label(score.tiebreak[4])
    )
  else
    return describe_high_card(score)
  end
end

function M.card_token(card)
  if not card then
    return "??"
  end
  local symbol = card.symbol or "?"
  return symbol .. M.get_suit(card)
end

function M.cards_to_tokens(cards)
  local tokens = {}
  if not cards then
    return tokens
  end
  for _, card in ipairs(cards) do
    tokens[#tokens + 1] = M.card_token(card)
  end
  return tokens
end

function M.cards_to_string(cards)
  return table.concat(M.cards_to_tokens(cards), " ")
end

return M
