local helper = require("tests.helpers.mock_vim")
helper.setup()

local ai = require("poker.ai")
local original_rng

before_each(function()
  original_rng = ai.set_rng(function()
    return 0.99
  end)
end)

after_each(function()
  ai.set_rng(original_rng)
end)

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

local function build_player(hole_cards, opts)
  opts = opts or {}
  return {
    name = opts.name or "Bot",
    stack = opts.stack or 400,
    bet_in_round = opts.bet_in_round or 0,
    hole_cards = hole_cards or {},
    folded = false,
    all_in = false,
  }
end

local function build_state(opts)
  opts = opts or {}
  return {
    board = opts.board or {},
    actions = opts.actions or {},
    pot = opts.pot or 0,
    current_bet = opts.current_bet or 0,
    min_raise = opts.min_raise or 20,
    to_call = opts.to_call or 0,
    players = opts.players or {},
  }
end

describe("evaluate_strength", function()
  it("scales straight draw potential by street", function()
    local player = build_player({ card(8, 0), card(7, 2) })
    local flop_state = build_state({
      board = { card(9, 1), card(6, 3), card(2, 0) },
      players = { player },
    })
    local flop_eval = ai.evaluate_strength(player, flop_state)
    assert.are.equal("flop", flop_eval.street)
    assert.is_true(math.abs(flop_eval.potential - 0.08) < 1e-6)

    local turn_state = build_state({
      board = { card(9, 1), card(6, 3), card(2, 0), card(12, 1) },
      players = { player },
    })
    local turn_eval = ai.evaluate_strength(player, turn_state)
    assert.are.equal("turn", turn_eval.street)
    assert.is_true(math.abs(turn_eval.potential - 0.04) < 1e-6)

    local river_state = build_state({
      board = { card(9, 1), card(6, 3), card(2, 0), card(12, 1), card(3, 2) },
      players = { player },
    })
    local river_eval = ai.evaluate_strength(player, river_state)
    assert.are.equal("river", river_eval.street)
    assert.are.equal(0, river_eval.potential)
  end)

  it("penalizes playing the board", function()
    local player = build_player({ card(2, 0), card(3, 1) })
    local state = build_state({
      board = { card(14, 2), card(13, 1), card(12, 0), card(11, 3), card(10, 2) },
      players = { player },
    })
    local eval = ai.evaluate_strength(player, state)
    assert.are.equal("river", eval.street)
    assert.is_true(eval.hole_card_contribution < 0)
    assert.is_true(eval.total < 0.75)
  end)

  it("adds nut flush draw bonus", function()
    local player = build_player({ card(14, 2), card(2, 2) })
    local state = build_state({
      board = { card(12, 2), card(9, 1), card(4, 0) },
      players = { player },
    })
    local eval = ai.evaluate_strength(player, state)
    assert.are.equal("flop", eval.street)
    assert.is_true(eval.potential >= 0.06 and eval.potential < 0.07)
  end)

  it("buckets preflop strength and applies multiway penalty", function()
    local premium = build_player({ card(14, 3), card(14, 2) })
    local medium = build_player({ card(9, 1), card(8, 1) })
    local trash = build_player({ card(7, 0), card(2, 3) })

    local heads_up = build_state({ players = { premium, medium } })
    local eval_premium = ai.evaluate_strength(premium, heads_up)
    assert.is_true(eval_premium.total > 0.9)

    local eval_medium = ai.evaluate_strength(medium, heads_up)
    assert.is_true(eval_medium.total >= 0.55 and eval_medium.total <= 0.7)

    local eval_trash = ai.evaluate_strength(trash, heads_up)
    assert.is_true(eval_trash.total >= 0.2 and eval_trash.total <= 0.32)

    local multiway = build_state({ players = { premium, medium, trash, build_player({ card(5, 1), card(5, 0) }) } })
    local eval_multi = ai.evaluate_strength(medium, multiway)
    assert.is_true(eval_multi.total < eval_medium.total)
  end)
end)

describe("ai.decide", function()
  it("value raises with premium made hands", function()
    local player = build_player({
      card(14, 2),
      card(13, 2),
    })
    local state = build_state({
      board = { card(10, 2), card(5, 2), card(2, 2), card(9, 1), card(3, 0) },
      actions = { "call", "fold", "raise" },
      pot = 200,
      current_bet = 40,
      min_raise = 20,
      to_call = 40,
      players = { player },
    })

    ai.set_rng(function()
      return 0.9
    end)
    local decision = ai.decide(player, state)
    assert.are.equal("raise", decision.action or decision[1])
  end)

  it("semi-bluff raises draws with stochastic frequency", function()
    local player = build_player({
      card(8, 2),
      card(7, 2),
    })
    local state = build_state({
      board = { card(9, 0), card(7, 1), card(6, 2) },
      actions = { "call", "fold", "raise" },
      pot = 120,
      current_bet = 10,
      min_raise = 20,
      to_call = 30,
      players = { player },
    })

    ai.set_rng(function()
      return 0.95
    end)
    local aggressive = ai.decide(player, state)
    assert.are.equal("raise", aggressive.action or aggressive[1])

    ai.set_rng(function()
      return 0.1
    end)
    local passive = ai.decide(player, state)
    assert.are.equal("call", passive)
  end)

  it("tightens calling thresholds in multiway pots", function()
    local player = build_player({
      card(9, 0),
      card(4, 1),
    })
    local board = { card(9, 2), card(5, 3), card(2, 1), card(12, 0) }
    local base_state = {
      board = board,
      actions = { "call", "fold", "raise" },
      pot = 100,
      current_bet = 50,
      min_raise = 20,
      to_call = 50,
    }

    local heads_up = build_state({
      board = base_state.board,
      actions = base_state.actions,
      pot = base_state.pot,
      current_bet = base_state.current_bet,
      min_raise = base_state.min_raise,
      to_call = base_state.to_call,
      players = { player },
    })
    local multiway = build_state({
      board = base_state.board,
      actions = base_state.actions,
      pot = base_state.pot,
      current_bet = base_state.current_bet,
      min_raise = base_state.min_raise,
      to_call = base_state.to_call,
      players = {
        player,
        build_player({ card(13, 0), card(2, 0) }),
        build_player({ card(6, 3), card(6, 1) }),
        build_player({ card(4, 2), card(3, 2) }),
      },
    })

    ai.set_rng(function()
      return 0.5
    end)
    assert.are.equal("call", ai.decide(player, heads_up))
    assert.are.equal("fold", ai.decide(player, multiway))
  end)

  it("opens preflop with premium buckets", function()
    local player = build_player({
      card(14, 3),
      card(14, 1),
    }, { bet_in_round = 0, stack = 500 })
    local state = build_state({
      board = {},
      actions = { "check", "bet", "fold" },
      pot = 30,
      current_bet = 0,
      min_raise = 20,
      to_call = 0,
      players = { player },
    })

    ai.set_rng(function()
      return 0.9
    end)
    local decision = ai.decide(player, state)
    assert.are.equal("bet", decision.action or decision[1])
    local target = decision.amount or decision[2]
    assert.is_true(target >= math.floor(state.min_raise * 2))
  end)
end)
