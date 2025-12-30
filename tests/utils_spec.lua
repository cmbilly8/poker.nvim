local helper = require("tests.helpers.mock_vim")
helper.setup()

local utils = require("poker.utils")

local function build_card(symbol, suit, revealed)
  return { symbol = symbol, suit = suit, revealed = revealed ~= false }
end

describe("utils.get_suit", function()
  local original_style

  before_each(function()
    original_style = utils.suit_style
    utils.suit_style = "black"
  end)

  after_each(function()
    utils.suit_style = original_style
  end)

  it("returns black suit symbols when revealed", function()
    local club = build_card("A", 0, true)
    local heart = build_card("K", 2, true)
    assert.are.equal("♣", utils.get_suit(club))
    assert.are.equal("♥", utils.get_suit(heart))
  end)

  it("returns white suit symbols when style is white", function()
    utils.suit_style = "white"
    local diamond = build_card("Q", 1, true)
    local spade = build_card("J", 3, true)
    assert.are.equal("♢", utils.get_suit(diamond))
    assert.are.equal("♤", utils.get_suit(spade))
  end)

  it("hides suit when the card is unrevealed", function()
    local hidden = build_card("9", 1, false)
    assert.are.equal("?", utils.get_suit(hidden))
  end)
end)

describe("utils token helpers", function()
  local original_style

  before_each(function()
    original_style = utils.suit_style
    utils.suit_style = "black"
  end)

  after_each(function()
    utils.suit_style = original_style
  end)

  it("builds a token for a revealed card", function()
    local card = build_card("J", 3, true)
    assert.are.equal("J♠", utils.card_token(card))
  end)

  it("returns ?? when card is missing", function()
    assert.are.equal("??", utils.card_token(nil))
  end)

  it("joins multiple cards into a string", function()
    local cards = {
      build_card("A", 0, true),
      build_card("7", 1, true),
    }
    assert.are.equal("A♣ 7♦", utils.cards_to_string(cards))
  end)
end)

describe("utils rank and hand descriptions", function()
  it("formats rank labels with fallbacks", function()
    assert.are.equal("A", utils.rank_label(14))
    assert.are.equal("9", utils.rank_label(9))
    assert.are.equal("21", utils.rank_label(21))
  end)

  it("returns hand names for numeric or score inputs", function()
    assert.are.equal("Flush", utils.hand_name(5))
    assert.are.equal("Two Pair", utils.hand_name({ category = 2 }))
    assert.are.equal("Unknown", utils.hand_name({ category = 42 }))
  end)

  it("describes hands with category-specific text", function()
    local straight_flush = { category = 8, tiebreak = { 14 } }
    local full_house = { category = 6, tiebreak = { 12, 9 } }
    local two_pair = { category = 2, tiebreak = { 14, 13, 12 } }
    local high_card = { category = 0, tiebreak = { 14, 11, 9, 7, 3 } }
    assert.are.equal("Straight Flush (A high)", utils.describe_hand(straight_flush))
    assert.are.equal("Full House (Q full of 9)", utils.describe_hand(full_house))
    assert.are.equal("Two Pair (A and K with Q kicker)", utils.describe_hand(two_pair))
    assert.are.equal("High Card (A J 9 7 3)", utils.describe_hand(high_card))
  end)
end)
