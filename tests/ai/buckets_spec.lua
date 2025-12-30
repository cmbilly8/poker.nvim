local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local buckets = require("poker.ai.range_buckets")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

describe("range buckets", function()
  it("assigns premium preflop buckets", function()
    local bucket = buckets.preflop_bucket({ card(14, 1), card(14, 2) }, "BTN", 6, 3)
    assert.are.equal(1, bucket)
    local strong = buckets.preflop_bucket({ card(14, 3), card(13, 3) }, "UTG", 6, 1)
    assert.is_true(strong <= 2)
  end)

  it("classifies postflop buckets by made hand and draws", function()
    local eval = {
      category = 5,
      potential = 0.1,
      made = 0.8,
      street = "flop",
      total = 0.82,
    }
    local bucket = buckets.postflop_bucket(eval, { card(14, 1), card(7, 1), card(2, 1) })
    assert.are.equal(2, bucket)
  end)

  it("includes bucket and equity in evaluate_strength output", function()
    local player = { hole_cards = { card(14, 1), card(13, 1) } }
    local state = {
      board = { card(9, 2), card(8, 2), card(2, 0) },
      players = { player, { id = 2 } },
    }
    local eval = ai.evaluate_strength(player, state)
    assert.is_not_nil(eval.bucket)
    assert.is_not_nil(eval.equity)
  end)
end)
