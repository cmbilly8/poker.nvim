local helper = require("tests.helpers.mock_vim")
helper.setup()

local evaluator = require("poker.hand_evaluator")

local function card(rank, suit)
  return {
    rank = rank,
    suit = suit,
    symbol = tostring(rank),
    revealed = true,
  }
end

local function assert_category(name, expected_category, hand)
  local score = evaluator.score_five(hand)
  assert.are.equal(expected_category, score.category, name)
end

describe("hand evaluator", function()
  it("detects every hand category", function()
    assert_category("high card", 0, {
      card(14, 0), card(11, 1), card(9, 2), card(6, 3), card(4, 0),
    })

    assert_category("one pair", 1, {
      card(10, 0), card(10, 1), card(4, 2), card(3, 3), card(2, 0),
    })

    assert_category("two pair", 2, {
      card(9, 0), card(9, 1), card(5, 2), card(5, 3), card(2, 0),
    })

    assert_category("three of a kind", 3, {
      card(8, 0), card(8, 1), card(8, 2), card(4, 3), card(2, 0),
    })

    assert_category("straight", 4, {
      card(9, 0), card(8, 1), card(7, 2), card(6, 3), card(5, 0),
    })

    assert_category("wheel straight", 4, {
      card(14, 0), card(5, 1), card(4, 2), card(3, 3), card(2, 0),
    })

    assert_category("flush", 5, {
      card(14, 2), card(12, 2), card(10, 2), card(6, 2), card(3, 2),
    })

    assert_category("full house", 6, {
      card(13, 0), card(13, 1), card(13, 2), card(4, 0), card(4, 1),
    })

    assert_category("four of a kind", 7, {
      card(11, 0), card(11, 1), card(11, 2), card(11, 3), card(3, 0),
    })

    assert_category("straight flush", 8, {
      card(10, 1), card(9, 1), card(8, 1), card(7, 1), card(6, 1),
    })
  end)

  it("chooses the best five cards from seven", function()
    local cards = {
      card(14, 0), card(14, 1), card(14, 2), card(9, 0),
      card(5, 1), card(4, 2), card(3, 3),
    }
    local best = evaluator.best_hand(cards)
    assert.are.equal(3, best.category)
    assert.are.same({ 14, 9, 5 }, best.tiebreak)
  end)

  it("identifies a flush over lower categories in best_hand", function()
    local cards = {
      card(14, 0), card(10, 0), card(8, 0), card(6, 0), card(2, 0),
      card(9, 1), card(9, 2),
    }
    local best = evaluator.best_hand(cards)
    assert.are.equal(5, best.category)
    assert.are.equal(14, best.tiebreak[1])
  end)
end)
