local M = {}

local RANK_SYMBOLS = {
  [2] = "2",
  [3] = "3",
  [4] = "4",
  [5] = "5",
  [6] = "6",
  [7] = "7",
  [8] = "8",
  [9] = "9",
  [10] = "10",
  [11] = "J",
  [12] = "Q",
  [13] = "K",
  [14] = "A",
}

-- Seed the RNG once using both wall clock and high resolution timers when available.
local function seed_rng()
  local seed = os.time()
  local ok, uv = pcall(function()
    return vim and (vim.uv or vim.loop)
  end)
  if ok and uv and uv.hrtime then
    local hi = uv.hrtime()
    seed = (seed + hi) % 0x7FFFFFFF
  end
  math.randomseed(seed)
end

seed_rng()

---Create a fresh ordered deck of 52 cards.
---@return table<integer, table>
function M.new_deck()
  local deck = {}
  for suit = 0, 3 do
    for rank = 2, 14 do
      deck[#deck + 1] = {
        suit = suit,
        rank = rank,
        symbol = RANK_SYMBOLS[rank] or tostring(rank),
        revealed = false,
      }
    end
  end
  return deck
end

---Return a shallow copy of a card table.
---@param card table|nil
---@return table|nil
function M.clone(card)
  if not card then
    return nil
  end
  return {
    suit = card.suit,
    rank = card.rank,
    symbol = card.symbol,
    revealed = card.revealed,
  }
end

---Clone a list of cards.
---@param cards table[]|nil
---@return table[]
function M.clone_many(cards)
  local copy = {}
  if not cards then
    return copy
  end
  for idx, card in ipairs(cards) do
    copy[idx] = M.clone(card)
  end
  return copy
end

local function default_rng(upper)
  return math.random(upper)
end

---In-place Fisher-Yates shuffle for a deck.
---@param deck table[]
---@param rng fun(upper: integer): integer
function M.shuffle(deck, rng)
  rng = rng or default_rng
  for idx = #deck, 2, -1 do
    local j = rng(idx)
    deck[idx], deck[j] = deck[j], deck[idx]
  end
end

---Create and shuffle a deck in one step.
---@param rng fun(upper: integer): integer
---@return table[]
function M.new_shuffled(rng)
  local deck = M.new_deck()
  M.shuffle(deck, rng)
  return deck
end

---Draw the top card from the deck, marking it revealed.
---@param deck table[]
---@return table|nil
function M.draw(deck)
  if not deck or #deck == 0 then
    return nil
  end
  local card = table.remove(deck)
  if card then
    card.revealed = true
  end
  return card
end

return M
