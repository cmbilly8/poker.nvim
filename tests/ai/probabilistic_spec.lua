local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

describe("probabilistic sampling", function()
  it("is deterministic with seeded RNG", function()
    local player = { id = 1, hole_cards = { card(14, 1), card(13, 2) } }
    local state = {
      board = { card(10, 1), card(5, 2), card(2, 3), card(9, 0), card(3, 1) },
      actions = { "call", "fold", "raise" },
      pot = 200,
      current_bet = 40,
      min_raise = 20,
      to_call = 40,
      players = { player, { id = 2 } },
    }
    ai.set_rng(function()
      return 0.05
    end)
    local first = ai.decide(player, state)
    ai.set_rng(function()
      return 0.05
    end)
    local second = ai.decide(player, state)
    assert.are.equal(first.action or first, second.action or second)
  end)
end)
