local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local strategy = require("poker.ai.strategy")

describe("ai.decide", function()
  local original_eval
  local original_rng
  local original_size
  local function card(rank, suit)
    return { rank = rank, suit = suit }
  end

  local function action_name(result)
    if type(result) == "table" then
      return result.action
    end
    return result
  end

  before_each(function()
    original_eval = ai.evaluate_strength
    original_rng = ai.set_rng(function()
      return 0.1
    end)
    original_size = strategy.select_bet_size
  end)

  after_each(function()
    ai.evaluate_strength = original_eval
    ai.set_rng(original_rng)
    strategy.select_bet_size = original_size
  end)

  it("calls to satisfy MDF with medium showdown value buckets", function()
    ai.evaluate_strength = function()
      return {
        street = "flop",
        bucket = 4,
        total = 0.4,
        equity = 0.35,
        potential = 0.05,
        fold_equity = 0.2,
      }
    end

    strategy.select_bet_size = function()
      return 40
    end

    local player = { id = 2, stack = 500, bet_in_round = 0 }
    local state = {
      actions = { "fold", "call", "raise" },
      to_call = 20,
      pot = 100,
      current_bet = 30,
      min_raise = 10,
      players = {
        { id = 1, folded = false },
        { id = 2, folded = false },
      },
    }

    local action = ai.decide(player, state)
    assert.are.equal("call", action)
  end)

  it("raises with draw heavy bucket when facing bets (oop check-raise bluff line)", function()
    ai.evaluate_strength = function()
      return {
        street = "flop",
        bucket = 7,
        total = 0.45,
        equity = 0.45,
        potential = 0.2,
        fold_equity = 0.4,
      }
    end

    strategy.select_bet_size = function()
      return 60
    end

    ai.set_rng(function()
      return 0.95
    end)

    local player = { id = 3, stack = 500, bet_in_round = 0 }
    local state = {
      actions = { "fold", "call", "raise" },
      to_call = 10,
      pot = 40,
      current_bet = 10,
      min_raise = 10,
      board = {
        { rank = 10, suit = 1 },
        { rank = 9, suit = 2 },
        { rank = 8, suit = 3 },
      },
      players = {
        { id = 1, folded = false },
        { id = 3, folded = false },
      },
    }

    local action = ai.decide(player, state)
    assert.is_table(action)
    assert.are.equal("raise", action.action)
    assert.is_true(action.amount > state.current_bet)
  end)

  it("never folds premium SB hands for just the blind", function()
    ai.set_rng(function()
      return 0
    end)

    local hands = {
      { card(14, 1), card(13, 1) }, -- AKs
      { card(14, 2), card(13, 3) }, -- AKo
      { card(12, 1), card(12, 2) }, -- QQ
      { card(14, 2), card(14, 3) }, -- AA
    }

    for _, hole_cards in ipairs(hands) do
      local player = { id = 1, stack = 500, bet_in_round = 10, hole_cards = hole_cards }
      local state = {
        actions = { "fold", "call", "raise" },
        to_call = 10,
        pot = 30,
        current_bet = 20,
        min_raise = 20,
        big_blind = 20,
        position = "SB",
        players = {
          { id = 1, folded = false },
          { id = 2, folded = false },
        },
      }
      local action = action_name(ai.decide(player, state))
      assert.are_not.equal("fold", action)
    end
  end)

  it("completes or raises when facing a limp in the SB with strong hands", function()
    ai.set_rng(function()
      return 0
    end)

    local player = {
      id = 1,
      stack = 500,
      bet_in_round = 10,
      hole_cards = { card(14, 4), card(13, 4) }, -- AKs
    }
    local state = {
      actions = { "fold", "call", "raise" },
      to_call = 10,
      pot = 50,
      current_bet = 20,
      min_raise = 20,
      big_blind = 20,
      position = "SB",
      players = {
        { id = 1, folded = false },
        { id = 2, folded = false },
        { id = 3, folded = false }, -- limper
      },
      preflop_raise_count = 0,
    }

    local action = action_name(ai.decide(player, state))
    assert.are_not.equal("fold", action)
  end)
end)
