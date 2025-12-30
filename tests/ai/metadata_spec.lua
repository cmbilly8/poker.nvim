local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local strategy = require("poker.ai.strategy")
local opponent_model = require("poker.ai.opponent_model")

describe("ai metadata awareness", function()
  local original_eval
  local original_rng
  local original_select
  local original_adjust
  local original_get_stats

  before_each(function()
    original_eval = ai.evaluate_strength
    original_rng = ai.set_rng(function()
      return 0.5
    end)
    original_select = strategy.select_bet_size
    original_adjust = strategy.adjust_for_opponent
    original_get_stats = opponent_model.get_stats
    strategy.select_bet_size = function(_, _, _, _, _, min_raise, current)
      current = current or 0
      min_raise = min_raise or 20
      return current + min_raise
    end
    strategy.adjust_for_opponent = function(_, dist)
      return dist
    end
    opponent_model.get_stats = function()
      return { fold_to_cbet = 0.4, aggression = 0.4 }
    end
  end)

  after_each(function()
    ai.evaluate_strength = original_eval
    ai.set_rng(original_rng)
    strategy.select_bet_size = original_select
    strategy.adjust_for_opponent = original_adjust
    opponent_model.get_stats = original_get_stats
  end)

  local function base_state()
    return {
      actions = { "fold", "call", "raise" },
      to_call = 20,
      pot = 30,
      current_bet = 20,
      min_raise = 20,
      big_blind = 20,
      players = {
        { id = 1, seat = 1 },
        { id = 2, seat = 2 },
        { id = 3, seat = 3 },
      },
      preflop_raise_count = 0,
      has_raised = false,
    }
  end

  it("opens wider on the button than under the gun", function()
    ai.evaluate_strength = function()
      return {
        street = "preflop",
        bucket = 4,
        total = 0.6,
        made = 0.2,
        equity = 0.55,
        potential = 0.1,
      }
    end

    local hero = { id = 1, stack = 1000, bet_in_round = 0 }

    local utg_state = base_state()
    utg_state.position = "UTG"
    utg_state.seat = 1

    local btn_state = base_state()
    btn_state.position = "BTN"
    btn_state.seat = 3

    ai.set_rng(function()
      return 0.5
    end)

    local utg_action = ai.decide(hero, utg_state)
    local btn_action = ai.decide(hero, btn_state)

    assert.are.equal("fold", utg_action)
    assert.is_table(btn_action)
    assert.are.equal("raise", btn_action.action)
  end)

  it("honors the configured blind size when protecting premium hands", function()
    ai.evaluate_strength = function()
      return {
        street = "preflop",
        bucket = 1,
        total = 0.95,
        made = 0.9,
        equity = 0.92,
        potential = 0.1,
      }
    end

    local hero = { id = 1, stack = 1000, bet_in_round = 0 }
    local state = base_state()
    state.big_blind = 150
    state.to_call = 150
    state.current_bet = 150
    state.min_raise = 150
    state.position = "SB"
    state.seat = 2

    ai.set_rng(function()
      return 0.99
    end)

    local decision = ai.decide(hero, state)
    if type(decision) == "table" then
      decision = decision.action
    end
    assert.are_not.equal("fold", decision)
  end)
end)
