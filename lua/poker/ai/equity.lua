local equity = {}

local BUCKET_EQUITY = {
  [1] = 0.78,
  [2] = 0.68,
  [3] = 0.58,
  [4] = 0.48,
  [5] = 0.35,
  [6] = 0.3,
}

local function board_wetness(board)
  local suits = {}
  local ranks = {}
  for _, card in ipairs(board or {}) do
    suits[card.suit] = (suits[card.suit] or 0) + 1
    ranks[#ranks + 1] = card.rank or 0
  end
  table.sort(ranks)
  local wet = false
  for _, c in pairs(suits) do
    if c >= 3 then
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

function equity.estimate(eval, bucket, player_count, board)
  player_count = player_count or 2
  bucket = bucket or 5
  local base = BUCKET_EQUITY[bucket] or 0.4
  if eval and eval.total then
    base = (base + eval.total) / 2
  end
  if eval and eval.potential then
    base = base + math.min(eval.potential, 0.2)
  end

  if board_wetness(board) then
    base = base - 0.05
  end

  local adjusted = base * (1 - 0.05 * math.max(player_count - 2, 0))
  if adjusted < 0 then
    adjusted = 0
  end
  if adjusted > 1 then
    adjusted = 1
  end

  local fold_equity = 0.35
    + (bucket <= 2 and 0.15 or 0)
    + (bucket >= 7 and 0.05 or 0)
    + (not board_wetness(board) and 0.05 or 0)
    - (math.max(player_count - 2, 0) * 0.05)
  if fold_equity < 0 then
    fold_equity = 0
  end
  if fold_equity > 0.9 then
    fold_equity = 0.9
  end

  assert(adjusted >= 0 and adjusted <= 1, "equity must be within [0,1]")

  return {
    equity = adjusted,
    fold_equity = fold_equity,
  }
end

return equity
