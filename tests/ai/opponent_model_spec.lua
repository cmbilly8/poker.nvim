local helper = require("tests.helpers.mock_vim")
helper.setup()

local model = require("poker.ai.opponent_model")

describe("opponent model", function()
  before_each(function()
    if model.reset then
      model.reset()
    end
  end)

  it("tracks actions and showdown results", function()
    model.record_action(1, "call", 20, "preflop")
    model.record_action(1, "raise", 40, "preflop")
    model.record_action(1, "fold", 0, "flop")
    model.record_showdown(1, true)

    local stats = model.get_stats(1)
    assert.is_true(stats.vpip > 0)
    assert.is_true(stats.pfr > 0)
    assert.is_true(stats.fold_to_cbet >= 0)
    assert.is_true(stats.wsd >= 0)
  end)

  it("resets tracked stats", function()
    model.record_action(1, "raise", 40, "preflop")
    model.record_showdown(1, true)

    local before = model.get_stats(1)
    assert.is_true(before.vpip > 0)
    assert.is_true(before.pfr > 0)

    model.reset()

    local after = model.get_stats(1)
    assert.are.equal(0, after.vpip)
    assert.are.equal(0, after.pfr)
    assert.are.equal(0, after.wtsd)
  end)
end)
