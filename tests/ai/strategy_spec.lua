local helper = require("tests.helpers.mock_vim")
helper.setup()

local strategy = require("poker.ai.strategy")

describe("strategy helpers", function()
  it("computes MDF and call frequency with bucket weight", function()
    local mdf = strategy.mdf_required(10, 30)
    assert.are.equal(0.75, mdf)

    local call_freq = strategy.compute_call_frequency({ bucket = 4 }, 4, 0.4, mdf)
    assert.are.equal(0.75, call_freq)
  end)

  it("adjusts distributions based on opponent tendencies", function()
    local dist = strategy.adjust_for_opponent({
      fold_to_cbet = 0.6,
      fold_to_raise = 0.6,
      aggression_factor = 0.2,
      vpip = 0.25,
    }, {
      fold = 0.3,
      call = 0.3,
      raise = 0.4,
    })

    assert.is_true(dist.raise > 0.4)
    local total = (dist.fold or 0) + (dist.call or 0) + (dist.raise or 0)
    assert.is_true(math.abs(total - 1.0) < 1e-6)
  end)

  it("computes oop check-raise probability for draw heavy buckets", function()
    local prob = strategy.oop_check_raise_probability({ potential = 0.2, fold_equity = 0.35 }, 7, 0.4, {
      { rank = 9, suit = 0 },
      { rank = 8, suit = 1 },
      { rank = 7, suit = 2 },
    })
    assert.is_true(prob > 0)
    assert.is_true(prob <= 0.25)
  end)

  it("suggests oop turn probes at expected frequencies", function()
    local adj = strategy.oop_probe_turn({ street = "turn" }, 3, 0.45, {
      { rank = 9, suit = 0 },
      { rank = 4, suit = 1 },
      { rank = 2, suit = 2 },
      { rank = 12, suit = 3 },
    })
    assert.is_true(adj.raise >= 0.1 and adj.raise <= 0.6)
  end)

  it("reduces bluff multiplier on the river", function()
    local flop_mult = strategy.bluff_value_ratio({}, 8, 0.25, "flop")
    local river_mult = strategy.bluff_value_ratio({}, 8, 0.25, "river")
    assert.is_true(flop_mult > river_mult)
    assert.is_true(river_mult < 1.0)
  end)
end)
