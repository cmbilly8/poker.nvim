local helper = require("tests.helpers.mock_vim")
helper.setup()

local strategy = require("poker.ai.strategy")
local ai = require("poker.ai")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

describe("c-bet and sizing", function()
  it("bets more frequently on dry boards than wet boards", function()
    local eval = { made = 0.6, potential = 0.05, street = "flop" }
    local dry_board = { card(14, 0), card(7, 1), card(2, 2) }
    local wet_board = { card(9, 0), card(8, 0), card(7, 0) }

    local dry_freq = strategy.cbet_frequency(eval, 2, dry_board, 2, true, 0.65)
    local wet_freq = strategy.cbet_frequency(eval, 2, wet_board, 2, true, 0.65)
    assert.is_true(dry_freq > wet_freq)
  end)

  it("selects discrete bet sizes by street", function()
    local flop_size = strategy.select_bet_size("flop", 2, "value", 200, 0, 20, 0, 1000)
    local turn_size = strategy.select_bet_size("turn", 2, "value", 200, 0, 20, 0, 1000)
    assert.is_true(flop_size ~= turn_size)
    assert.is_true(flop_size >= 20)
  end)

  it("respects min raise and stack cap", function()
    local size = strategy.select_bet_size("river", 1, "value", 500, 100, 50, 200, 120)
    assert.is_true(size <= 200 + 100 + 120)
    assert.is_true(size >= 200 + 50)
  end)
end)
