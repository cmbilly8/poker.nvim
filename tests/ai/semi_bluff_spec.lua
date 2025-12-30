local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local opponent_model = require("poker.ai.opponent_model")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

local function build_state(opts)
  opts = opts or {}
  return {
    board = opts.board or {},
    actions = opts.actions or { "call", "fold", "raise" },
    pot = opts.pot or 200,
    current_bet = opts.current_bet or 20,
    min_raise = opts.min_raise or 20,
    to_call = opts.to_call or 20,
    players = opts.players or {},
  }
end

describe("semi-bluff logic", function()
  before_each(function()
    ai.set_rng(function()
      return 0.95
    end)
  end)

  it("raises strong draws and folds trash", function()
    local player = { id = 1, hole_cards = { card(8, 1), card(7, 1) } }
    local state = build_state({
      board = { card(9, 2), card(6, 3), card(2, 0) },
      players = { player, { id = 2 }, { id = 3 } },
      to_call = 30,
    })
    local action = ai.decide(player, state)
    assert.are.equal("raise", action.action or action[1])

    local weak = { id = 4, hole_cards = { card(3, 0), card(8, 3) } }
    local weak_state = build_state({
      board = { card(14, 1), card(7, 2), card(2, 0) },
      players = { weak, { id = 2 } },
      to_call = 50,
    })
    local decision = ai.decide(weak, weak_state)
    assert.are.equal("fold", decision)
  end)

  it("adjusts aggression using opponent fold tendencies", function()
    opponent_model.record_action(99, "bet", 50, "flop")
    opponent_model.record_action(99, "fold", 0, "flop")
    local player = { id = 1, hole_cards = { card(10, 1), card(9, 1) } }
    local state = build_state({
      board = { card(8, 2), card(7, 3), card(2, 0) },
      players = { player, { id = 99 } },
      to_call = 30,
    })
    ai.set_rng(function()
      return 0.9
    end)
    local action = ai.decide(player, state)
    assert.are.equal("raise", action.action or action[1])
  end)
end)
