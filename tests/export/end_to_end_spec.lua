local helper = require("tests.helpers.mock_vim")
helper.setup()

local acpc = require("poker.export.acpc")
local ps = require("poker.export.pokerstars")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

describe("hand history end-to-end", function()
  it("serializes a 6-max hand to both formats", function()
    local hand = {
      id = 8888,
      config = { small_blind = 10, big_blind = 20, starting_stack = 2000, table_name = "SixMax" },
      button_index = 3,
      players = {
        { id = 1, name = "P1", seat = 1, stack_start = 2000, hole_cards = { card(5, 0), card(5, 1) }, folded = true },
        { id = 2, name = "P2", seat = 2, stack_start = 2000, hole_cards = { card(9, 3), card(7, 2) }, folded = true },
        { id = 3, name = "Hero", seat = 3, is_human = true, stack_start = 2000, hole_cards = { card(14, 3), card(13, 2) }, folded = false },
        { id = 4, name = "P4", seat = 4, stack_start = 2000, hole_cards = { card(8, 0), card(2, 0) }, folded = true },
        { id = 5, name = "P5", seat = 5, stack_start = 2000, hole_cards = { card(6, 1), card(6, 2) }, folded = true },
        { id = 6, name = "P6", seat = 6, stack_start = 2000, hole_cards = { card(4, 3), card(3, 1) }, folded = true },
      },
      actions = {
        { street = "preflop", player_id = 1, player_name = "P1", action = "blind", amount = 10, total = 10, info = { label = "posts small blind" } },
        { street = "preflop", player_id = 2, player_name = "P2", action = "blind", amount = 20, total = 20, info = { label = "posts big blind" } },
        { street = "preflop", player_id = 3, player_name = "Hero", action = "call", amount = 20, total = 20 },
        { street = "preflop", player_id = 4, player_name = "P4", action = "fold", amount = 0 },
        { street = "preflop", player_id = 5, player_name = "P5", action = "fold", amount = 0 },
        { street = "preflop", player_id = 6, player_name = "P6", action = "fold", amount = 0 },
        { street = "preflop", player_id = 1, player_name = "P1", action = "call", amount = 10, total = 20 },
        { street = "preflop", player_id = 2, player_name = "P2", action = "check", amount = 0, total = 20 },
        { street = "flop", player_id = 3, player_name = "Hero", action = "bet", amount = 40, total = 40 },
        { street = "flop", player_id = 1, player_name = "P1", action = "fold", amount = 0 },
        { street = "flop", player_id = 2, player_name = "P2", action = "fold", amount = 0 },
      },
      board = { card(14, 0), card(13, 1), card(2, 2) },
      pot = 100,
      showdown = {
        hand = "No Showdown",
        winners = { { player = { id = 3, name = "Hero" }, amount = 100 } },
      },
    }

    local acpc_state = acpc.serialize_state(hand.id, hand)
    assert.are.equal("STATE:8888:r10r20cfffcc/r40ff//:xx|xx|AsKh|xx|xx|xx:AcKd2h", acpc_state)

    local ps_text = ps.serialize_hand(hand)
    assert.is_true(ps_text:find("Table 'SixMax' 6-max", 1, true) ~= nil)
    assert.is_true(ps_text:find("*** FLOP *** [Ac Kd 2h]", 1, true) ~= nil)
    assert.is_true(ps_text:find("Hero: bets $0.40", 1, true) ~= nil)
    assert.is_true(ps_text:find("Seat 3: Hero showed [As Kh] and won ($1.00)", 1, true) ~= nil)
  end)
end)
