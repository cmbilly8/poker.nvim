local helper = require("tests.helpers.mock_vim")
helper.setup()

local cards = require("poker.cards")

local function card_key(card)
  return string.format("%d-%d", card.suit, card.rank)
end

describe("cards", function()
  it("creates a unique 52 card deck", function()
    local deck = cards.new_deck()
    assert.are.equal(52, #deck)
    local seen = {}
    for _, card in ipairs(deck) do
      local key = card_key(card)
      assert.is_nil(seen[key], "duplicate card: " .. key)
      seen[key] = true
    end
  end)

  it("draws from the top and marks cards revealed", function()
    local deck = cards.new_deck()
    local original_top = deck[#deck]
    local drawn = cards.draw(deck)
    assert.are.equal(original_top.rank, drawn.rank)
    assert.are.equal(original_top.suit, drawn.suit)
    assert.is_true(drawn.revealed)
    assert.are.equal(51, #deck)
  end)
end)
