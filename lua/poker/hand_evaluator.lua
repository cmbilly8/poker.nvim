local cards = require("poker.cards")

local M = {}

local function sorted_copy(hand)
  local copy = cards.clone_many(hand)
  table.sort(copy, function(a, b)
    if a.rank == b.rank then
      return a.suit < b.suit
    end
    return a.rank > b.rank
  end)
  return copy
end

local function extract_rank_groups(sorted)
  local counts = {}
  for _, card in ipairs(sorted) do
    counts[card.rank] = (counts[card.rank] or 0) + 1
  end

  local groups = {}
  for rank, count in pairs(counts) do
    groups[#groups + 1] = { rank = rank, count = count }
  end

  table.sort(groups, function(lhs, rhs)
    if lhs.count == rhs.count then
      return lhs.rank > rhs.rank
    end
    return lhs.count > rhs.count
  end)

  return groups
end

local function is_flush(sorted)
  for idx = 2, #sorted do
    if sorted[idx].suit ~= sorted[1].suit then
      return false
    end
  end
  return true
end

local function sorted_ranks(sorted)
  local ranks = {}
  for idx, card in ipairs(sorted) do
    ranks[idx] = card.rank
  end
  table.sort(ranks, function(a, b)
    return a > b
  end)
  return ranks
end

local function straight_info(ranks)
  local is_straight = true
  for idx = 1, 4 do
    if ranks[idx] - 1 ~= ranks[idx + 1] then
      is_straight = false
      break
    end
  end

  local high_card = ranks[1]
  if is_straight then
    return true, high_card, ranks
  end

  local wheel = { 14, 5, 4, 3, 2 }
  for idx = 1, 5 do
    if ranks[idx] ~= wheel[idx] then
      return false, high_card, ranks
    end
  end

  return true, 5, { 5, 4, 3, 2, 1 }
end

---Score a five-card poker hand.
---@param hand table[]
---@return table score
function M.score_five(hand)
  local sorted = sorted_copy(hand)
  local rank_groups = extract_rank_groups(sorted)
  local flush = is_flush(sorted)
  local ranks = sorted_ranks(sorted)
  local straight, straight_high, straight_ranks = straight_info(ranks)

  local category
  local tiebreak

  if straight and flush then
    category = 8
    tiebreak = { straight_high }
  elseif rank_groups[1].count == 4 then
    category = 7
    tiebreak = { rank_groups[1].rank, rank_groups[2].rank }
  elseif rank_groups[1].count == 3 and rank_groups[2] and rank_groups[2].count == 2 then
    category = 6
    tiebreak = { rank_groups[1].rank, rank_groups[2].rank }
  elseif flush then
    category = 5
    tiebreak = straight_ranks
  elseif straight then
    category = 4
    tiebreak = { straight_high }
  elseif rank_groups[1].count == 3 then
    category = 3
    local kickers = {}
    for _, group in ipairs(rank_groups) do
      if group.count == 1 then
        kickers[#kickers + 1] = group.rank
      end
    end
    table.sort(kickers, function(a, b)
      return a > b
    end)
    tiebreak = { rank_groups[1].rank, kickers[1], kickers[2] }
  elseif rank_groups[1].count == 2 and rank_groups[2] and rank_groups[2].count == 2 then
    category = 2
    local kicker = rank_groups[3] and rank_groups[3].rank or straight_ranks[#straight_ranks]
    local high_pair = math.max(rank_groups[1].rank, rank_groups[2].rank)
    local low_pair = math.min(rank_groups[1].rank, rank_groups[2].rank)
    tiebreak = { high_pair, low_pair, kicker }
  elseif rank_groups[1].count == 2 then
    category = 1
    local kickers = {}
    for _, group in ipairs(rank_groups) do
      if group.count == 1 then
        kickers[#kickers + 1] = group.rank
      end
    end
    table.sort(kickers, function(a, b)
      return a > b
    end)
    tiebreak = {
      rank_groups[1].rank,
      kickers[1],
      kickers[2],
      kickers[3],
    }
  else
    category = 0
    tiebreak = straight_ranks
  end

  return {
    category = category,
    tiebreak = tiebreak,
    cards = sorted,
  }
end

---Compare two score tables.
---@param lhs table
---@param rhs table
---@return boolean
function M.is_better(lhs, rhs)
  if lhs.category ~= rhs.category then
    return lhs.category > rhs.category
  end

  local max_len = math.max(#lhs.tiebreak, #rhs.tiebreak)
  for idx = 1, max_len do
    local a = lhs.tiebreak[idx] or 0
    local b = rhs.tiebreak[idx] or 0
    if a ~= b then
      return a > b
    end
  end

  return false
end

---Check whether two score tables represent the same value.
---@param lhs table
---@param rhs table
---@return boolean
function M.are_equal(lhs, rhs)
  return not M.is_better(lhs, rhs) and not M.is_better(rhs, lhs)
end

---Return the best five-card hand from a list of at least five cards.
---@param all_cards table[]
---@return table
function M.best_hand(all_cards)
  if not all_cards or #all_cards < 5 then
    return nil
  end

  local best
  local n = #all_cards
  local indices = { 1, 2, 3, 4, 5 }

  local function evaluate_current()
    local selection = {}
    for _, idx in ipairs(indices) do
      selection[#selection + 1] = all_cards[idx]
    end
    local score = M.score_five(selection)
    if not best or M.is_better(score, best) then
      best = score
    end
  end

  local function advance(pos)
    if pos == 0 then
      return false
    end
    if indices[pos] < n - (5 - pos) then
      indices[pos] = indices[pos] + 1
      for i = pos + 1, 5 do
        indices[i] = indices[i - 1] + 1
      end
      return true
    end
    return advance(pos - 1)
  end

  while true do
    evaluate_current()
    if not advance(5) then
      break
    end
  end

  return best
end

return M
