local helper = require("tests.helpers.mock_vim")
helper.setup()

local ps = require("poker.export.pokerstars")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

local function sample_hand()
  return {
    id = 12345,
    config = { small_blind = 10, big_blind = 25, starting_stack = 1000, table_name = "TestTable" },
    button_index = 2,
    players = {
      { id = 1, name = "P1", seat = 1, is_human = true, stack_start = 1000, hole_cards = { card(14, 3), card(13, 2) }, folded = false },
      { id = 2, name = "P2", seat = 2, stack_start = 1000, hole_cards = { card(12, 0), card(12, 1) }, folded = false },
    },
    actions = {
      { street = "preflop", player_id = 1, player_name = "P1", action = "blind", amount = 10, total = 10, info = { label = "posts small blind" } },
      { street = "preflop", player_id = 2, player_name = "P2", action = "blind", amount = 25, total = 25, info = { label = "posts big blind" } },
      { street = "preflop", player_id = 1, player_name = "P1", action = "call", amount = 15, total = 25 },
      { street = "preflop", player_id = 2, player_name = "P2", action = "check", amount = 0, total = 25 },
      { street = "flop", player_id = 1, player_name = "P1", action = "bet", amount = 50, total = 50 },
      { street = "flop", player_id = 2, player_name = "P2", action = "call", amount = 50, total = 50 },
      { street = "turn", player_id = 1, player_name = "P1", action = "check", amount = 0, total = 50 },
      { street = "turn", player_id = 2, player_name = "P2", action = "check", amount = 0, total = 50 },
      { street = "river", player_id = 1, player_name = "P1", action = "check", amount = 0, total = 50 },
      { street = "river", player_id = 2, player_name = "P2", action = "check", amount = 0, total = 50 },
    },
    board = { card(14, 0), card(7, 2), card(2, 1), card(13, 0), card(5, 3) },
    pot = 150,
    showdown = {
      hand = "Pair of Aces",
      winners = { { player = { id = 1, name = "P1" }, amount = 150 } },
    },
  }
end

describe("pokerstars export", function()
  it("formats a full hand history", function()
    local hand = sample_hand()
    local text = ps.serialize_hand(hand)
    local expected = table.concat({
      "PokerStars Hand #12345:  Hold'em No Limit ($0.10/$0.25 USD)",
      "Table 'TestTable' 2-max Seat #2 is the button",
      "Seat 1: P1 ($10.00 in chips)",
      "Seat 2: P2 ($10.00 in chips)",
      "*** HOLE CARDS ***",
      "Dealt to P1 [As Kh]",
      "P1: posts small blind $0.10",
      "P2: posts big blind $0.25",
      "P1: calls $0.15",
      "P2: checks",
      "*** FLOP *** [Ac 7h 2d]",
      "P1: bets $0.50",
      "P2: calls $0.50",
      "*** TURN *** [Ac 7h 2d Kc]",
      "P1: checks",
      "P2: checks",
      "*** RIVER *** [Ac 7h 2d Kc 5s]",
      "P1: checks",
      "P2: checks",
      "*** SHOW DOWN ***",
      "P1: showed [As Kh] and won ($1.50) with Pair of Aces",
      "P2: showed [Qc Qd] and lost",
      "*** SUMMARY ***",
      "Total pot $1.50 | Rake $0.00",
      "Board [Ac 7h 2d Kc 5s]",
      "Seat 1: P1 showed [As Kh] and won ($1.50)",
      "Seat 2: P2 showed [Qc Qd] and lost",
    }, "\n")

    assert.are.equal(expected, text)
  end)
end)
