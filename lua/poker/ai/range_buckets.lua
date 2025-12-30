local ranges = require("poker.ai.preflop_ranges")

local buckets = {}

local function position_from_state(position, player_count, seat)
  if position then
    return position
  end
  player_count = player_count or 6
  seat = seat or 1
  local order = { "UTG", "MP", "CO", "BTN", "SB", "BB" }
  local idx = ((seat - 1) % #order) + 1
  return order[idx]
end

function buckets.preflop_bucket(hole_cards, position, player_count, seat)
  position = position_from_state(position, player_count, seat)
  return ranges.lookup_bucket(hole_cards and hole_cards[1], hole_cards and hole_cards[2], position)
end

local function board_texture(board)
  local suits = {}
  local ranks = {}
  for _, card in ipairs(board or {}) do
    suits[card.suit] = (suits[card.suit] or 0) + 1
    ranks[#ranks + 1] = card.rank or 0
  end
  table.sort(ranks)
  local is_wet = false
  if #board >= 3 then
    for _, count in pairs(suits) do
      if count >= 3 then
        is_wet = true
        break
      end
    end
    if not is_wet then
      local spread = (ranks[#ranks] or 0) - (ranks[1] or 0)
      if spread <= 4 then
        is_wet = true
      end
    end
  end
  return is_wet and "wet" or "dry"
end

function buckets.postflop_bucket(eval, board, player, state)
  eval = eval or {}
  local category = eval.category or 0
  local potential = eval.potential or 0
  local made = eval.made or 0
  local street = eval.street or "flop"
  local texture = board_texture(board)

  if category >= 7 then
    return 1
  elseif category >= 5 then
    return 2
  elseif category == 4 or category == 3 then
    return 3
  elseif category == 2 then
    return texture == "wet" and 3 or 4
  elseif potential >= 0.08 then
    return 3
  elseif made >= 0.5 then
    return 4
  end

  if street == "flop" and potential >= 0.06 then
    return 4
  end

  return 5
end

return buckets
