local ranges = {}

local function combo_key(card1, card2)
  local ranks = { card1.rank or 0, card2.rank or 0 }
  table.sort(ranks, function(a, b)
    return a > b
  end)
  local suited = card1.suit ~= nil and card1.suit == card2.suit
  local r1 = ranks[1]
  local r2 = ranks[2]
  local map = {
    [14] = "A",
    [13] = "K",
    [12] = "Q",
    [11] = "J",
    [10] = "T",
    [9] = "9",
    [8] = "8",
    [7] = "7",
    [6] = "6",
    [5] = "5",
    [4] = "4",
    [3] = "3",
    [2] = "2",
  }
  local suited_flag = suited and "s" or "o"
  if r1 == r2 then
    suited_flag = ""
  end
  return string.format("%s%s%s", map[r1] or "?", map[r2] or "?", suited_flag)
end

local POSITIONS = { "UTG", "MP", "CO", "BTN", "SB", "BB" }

local function build_range(list)
  local set = {}
  for _, key in ipairs(list) do
    set[key] = true
  end
  return set
end

ranges.positions = POSITIONS

ranges.preflop = {
  premium = build_range({ "AA", "KK", "QQ", "AKs" }),
  strong = build_range({ "JJ", "TT", "AQs", "AKo", "KQs" }),
  medium = build_range({
    "99",
    "88",
    "77",
    "AJs",
    "ATs",
    "KJs",
    "QJs",
    "JTs",
    "T9s",
    "98s",
    "87s",
    "76s",
    "65s",
    "54s",
    "AQo",
    "AJo",
    "KQo",
  }),
  weak = build_range({
    "66",
    "55",
    "44",
    "33",
    "22",
    "KTo",
    "QJo",
    "QTs",
    "JTo",
    "T8s",
    "97s",
    "86s",
    "75s",
    "64s",
    "53s",
  }),
}

function ranges.lookup_bucket(card1, card2, position)
  if not card1 or not card2 then
    return 5
  end
  local key = combo_key(card1, card2)
  local pos = position or "MP"
  pos = pos:upper()
  local bucket = 5
  if ranges.preflop.premium[key] then
    bucket = 1
  elseif ranges.preflop.strong[key] then
    bucket = 2
  elseif ranges.preflop.medium[key] then
    bucket = 3
  elseif ranges.preflop.weak[key] then
    bucket = 4
  end

  if pos == "UTG" and bucket >= 3 then
    bucket = bucket + 1
  elseif (pos == "BTN" or pos == "CO") and bucket > 1 then
    bucket = bucket - 1
  end

  if bucket < 1 then
    bucket = 1
  end
  if bucket > 6 then
    bucket = 6
  end
  return bucket
end

return ranges
