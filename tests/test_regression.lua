local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local range_buckets = require("poker.ai.range_buckets")
local strategy = require("poker.ai.strategy")

local function seeded_rng()
  local seed = 1234567
  return function()
    seed = (1103515245 * seed + 12345) % 0x7fffffff
    return (seed % 10000) / 10000
  end
end

local function random_card(rng)
  return {
    rank = math.floor(rng() * 13) + 2,
    suit = math.floor(rng() * 4),
    revealed = true,
  }
end

local function random_hand(rng)
  return { random_card(rng), random_card(rng) }
end

describe("regression frequencies", function()
  local original_eval
  local original_rng

  before_each(function()
    original_eval = ai.evaluate_strength
    original_rng = ai.set_rng(seeded_rng())
    math.randomseed(42)
  end)

  after_each(function()
    ai.evaluate_strength = original_eval
    ai.set_rng(original_rng)
  end)

  it("keeps preflop frequencies within target ranges", function()
    local rng = seeded_rng()
    ai.set_rng(rng)
    local total = 0
    local raises = 0
    local calls = 0
    local folds = 0

    local positions = { "UTG", "MP", "CO", "BTN", "SB" }

    for i = 1, 10000 do
      local player = { id = i, hole_cards = random_hand(rng) }
      local state = {
        street = "pre-flop",
        position = positions[(i % #positions) + 1],
        actions = { "fold", "call", "raise" },
        to_call = 20,
        pot = 30,
        current_bet = 20,
        min_raise = 20,
        players = { player },
      }
      local action = ai.decide(player, state)
      total = total + 1
      if type(action) == "table" then
        action = action.action
      end
      if action == "raise" then
        raises = raises + 1
      elseif action == "call" then
        calls = calls + 1
      else
        folds = folds + 1
      end
    end

    for i = 1, 10000 do
      local player = { id = i + 20000, hole_cards = random_hand(rng) }
      local state = {
        street = "pre-flop",
        position = positions[(i % #positions) + 1],
        actions = { "fold", "call", "raise" },
        to_call = 40,
        pot = 80,
        current_bet = 40,
        min_raise = 40,
        players = { player },
        has_raised = true,
      }
      local action = ai.decide(player, state)
      total = total + 1
      if type(action) == "table" then
        action = action.action
      end
      if action == "raise" then
        raises = raises + 1
      elseif action == "call" then
        calls = calls + 1
      else
        folds = folds + 1
      end
    end

    local raise_pct = raises / total
    local call_pct = calls / total
    local fold_pct = folds / total

    assert.is_true(raise_pct >= 0.15 and raise_pct <= 0.22, ("raise pct %.3f"):format(raise_pct))
    assert.is_true(call_pct >= 0.10 and call_pct <= 0.18, ("call pct %.3f"):format(call_pct))
    assert.is_true(fold_pct >= 0.60 and fold_pct <= 0.70, ("fold pct %.3f"):format(fold_pct))
  end)

  it("maintains postflop folds above minimum thresholds", function()
    local rng = seeded_rng()
    ai.set_rng(rng)
    ai.evaluate_strength = function()
      return {
        street = "flop",
        bucket = math.floor(rng() * 6) + 1,
        total = rng(),
        equity = rng(),
        potential = rng() * 0.2,
        fold_equity = 0.3,
      }
    end

    local folds = 0
    local total = 0
    for _ = 1, 10000 do
      local player = { id = 1, stack = 500 }
      local state = {
        street = "flop",
        actions = { "fold", "call", "raise" },
        to_call = 50,
        pot = 100,
        current_bet = 50,
        min_raise = 50,
        players = { player, { id = 2 } },
      }
      local action = ai.decide(player, state)
      total = total + 1
      local name = type(action) == "table" and action.action or action
      if name == "fold" then
        folds = folds + 1
      end
    end

    local fold_pct = folds / total
    assert.is_true(fold_pct >= 0.12, ("fold pct %.3f"):format(fold_pct))
  end)

  it("adjusts bluffing based on opponent model stats", function()
    local base = strategy.adjust_for_opponent({}, { fold = 0.3, call = 0.3, raise = 0.4 })
    local overfolder = strategy.adjust_for_opponent({ fold_to_raise = 0.6, fold_to_cbet = 0.7 }, { fold = 0.3, call = 0.3, raise = 0.4 })
    local nit = strategy.adjust_for_opponent({ vpip = 0.1, fold_to_raise = 0.1 }, { fold = 0.3, call = 0.3, raise = 0.4 })

    assert.is_true(overfolder.raise > base.raise)
    assert.is_true(nit.raise < base.raise)
  end)

  it("always resolves to fold/call/raise actions", function()
    ai.evaluate_strength = function()
      return {
        street = "flop",
        bucket = 4,
        total = 0.4,
        equity = 0.4,
        potential = 0.05,
        fold_equity = 0.3,
      }
    end
    for _ = 1, 200 do
      local player = { id = 1 }
      local state = {
        street = "flop",
        actions = { "fold", "call", "raise" },
        to_call = 10,
        pot = 40,
        current_bet = 10,
        min_raise = 10,
        players = { player, { id = 2 } },
      }
      local action = ai.decide(player, state)
      local name = type(action) == "table" and action.action or action
      assert.is_true(name == "fold" or name == "call" or name == "raise")
    end
  end)
end)
