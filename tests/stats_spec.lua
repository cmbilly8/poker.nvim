local helper = require("tests.helpers.mock_vim")
helper.setup()

local stats = require("poker.stats")

local function approx(actual, expected)
  return math.abs(actual - expected) < 0.0001
end

describe("stats tracking", function()
  it("tracks preflop, c-bet, defense, and fold rates", function()
    local store = stats.new_store()
    local log = {
      players = {
        { id = 1, name = "You" },
        { id = 2, name = "Villain" },
      },
      board = { {}, {}, {} },
      actions = {
        { street = "preflop", player_id = 1, action = "blind", info = { label = "posts small blind" } },
        { street = "preflop", player_id = 2, action = "blind", info = { label = "posts big blind" } },
        { street = "preflop", player_id = 1, action = "raise" },
        { street = "preflop", player_id = 2, action = "call" },
        { street = "flop", player_id = 1, action = "bet" },
        { street = "flop", player_id = 2, action = "fold" },
      },
      showdown = {
        hand = "All opponents folded",
        winners = { { player = { id = 1 } } },
      },
      players_final = {
        { id = 1, folded = false },
        { id = 2, folded = true },
      },
    }

    stats.record_hand(store, log)

    local hero = stats.get_player_stats(store, 1)
    local villain = stats.get_player_stats(store, 2)

    assert.is_true(approx(hero.vpip, 1))
    assert.is_true(approx(hero.pfr, 1))
    assert.is_true(villain.three_bet == nil or approx(villain.three_bet, 0))
    assert.is_true(approx(villain.fold_to_cbet, 1))
    assert.is_true(approx(villain.bb_defense, 1))
    assert.is_true(approx(villain.fold_flop, 1))
    assert.is_true(hero.aggression_factor == math.huge)
  end)

  it("tracks showdown results", function()
    local store = stats.new_store()
    local log = {
      players = {
        { id = 1, name = "You" },
        { id = 2, name = "Villain" },
      },
      board = { {}, {}, {}, {}, {} },
      actions = {
        { street = "preflop", player_id = 1, action = "blind", info = { label = "posts small blind" } },
        { street = "preflop", player_id = 2, action = "blind", info = { label = "posts big blind" } },
        { street = "preflop", player_id = 1, action = "call" },
        { street = "preflop", player_id = 2, action = "check" },
        { street = "flop", player_id = 1, action = "check" },
        { street = "flop", player_id = 2, action = "bet" },
        { street = "flop", player_id = 1, action = "call" },
        { street = "turn", player_id = 1, action = "check" },
        { street = "turn", player_id = 2, action = "check" },
        { street = "river", player_id = 1, action = "bet" },
        { street = "river", player_id = 2, action = "call" },
      },
      showdown = {
        hand = "Pair of Aces",
        winners = { { player = { id = 1 } } },
      },
      players_final = {
        { id = 1, folded = false },
        { id = 2, folded = false },
      },
    }

    stats.record_hand(store, log)

    local hero = stats.get_player_stats(store, 1)
    local villain = stats.get_player_stats(store, 2)

    assert.is_true(approx(hero.wtsd, 1))
    assert.is_true(approx(villain.wtsd, 1))
    assert.is_true(approx(hero.wsd, 1))
    assert.is_true(approx(villain.wsd, 0))
  end)
end)
