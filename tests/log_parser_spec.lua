local helper = require("tests.helpers.mock_vim")
helper.setup()

local parser = require("poker.log_parser")

describe("log parser", function()
  it("ignores blind raises when detecting preflop action frequencies", function()
    local observed = parser.parse_lines({
      "blind ante 0 15 30",
      "STATE:1:r15r30r60///:xx|xx:",
    })
    assert.are.equal(1, observed.preflop.open)
    assert.are.equal(1, observed.preflop.total)
  end)

  it("respects provided blind size when no gamedef line exists", function()
    local observed = parser.parse_lines({
      "STATE:1:r10r20r45///:xx|xx:",
    }, 20)
    assert.are.equal(1, observed.preflop.open)
    assert.are.equal(1, observed.preflop.total)
  end)

  it("normalizes counts for all streets", function()
    local analysis = parser.normalize_counts({
      preflop = { open = 2, call = 1, fold = 1, total = 4 },
      flop = { raise = 1, call = 1, fold = 0, total = 2 },
      turn = { raise = 0, call = 3, fold = 1, total = 4 },
      river = { raise = 0, call = 0, fold = 0, total = 0 },
    })
    assert.are.same({
      open = 0.5,
      call = 0.25,
      fold = 0.25,
      total = 4,
    }, analysis.preflop)
    assert.are.same({
      raise = 0.5,
      call = 0.5,
      fold = 0,
      total = 2,
    }, analysis.flop)
    assert.are.same({
      raise = 0,
      call = 0.75,
      fold = 0.25,
      total = 4,
    }, analysis.turn)
    assert.are.same({
      raise = 0,
      call = 0,
      fold = 0,
      total = 0,
    }, analysis.river)
  end)
end)
