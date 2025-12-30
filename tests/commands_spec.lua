local helper = require("tests.helpers.mock_vim")
helper.setup()

package.preload["plenary.popup"] = function()
  return {
    create = function()
      local id = vim._mock.next_win
      vim._mock.next_win = vim._mock.next_win + 1
      vim._mock.windows[id] = { width = vim.o.columns, valid = true }
      return id, {}
    end,
  }
end

local match = require("poker.match")
local window = require("poker.window")
local commands = require("poker.commands")

describe("commands actions", function()
  local original = {}

  before_each(function()
    vim._mock.reset()
    original.start_session = match.start_session
    original.start_hand = match.start_hand
    original.skip_to_player_turn = match.skip_to_player_turn
    original.available_actions = match.available_actions
    original.player_action = match.player_action
    original.get_state = match.get_state
    original.config = vim.deepcopy(match.config)
    original.players = match.players
    original.current_state = match.current_state
    original.current_player_index = match.current_player_index
    original.render = window.render
    original.destroy = window.destroy
    original.toggle_stats = window.toggle_stats
    original.reset_stats = window.reset_stats
  end)

  after_each(function()
    match.start_session = original.start_session
    match.start_hand = original.start_hand
    match.skip_to_player_turn = original.skip_to_player_turn
    match.available_actions = original.available_actions
    match.player_action = original.player_action
    match.get_state = original.get_state
    match.config = vim.deepcopy(original.config)
    match.players = original.players
    match.current_state = original.current_state
    match.current_player_index = original.current_player_index
    window.render = original.render
    window.destroy = original.destroy
    window.toggle_stats = original.toggle_stats
    window.reset_stats = original.reset_stats
  end)

  local function run_command(name)
    commands.create_commands()
    assert.is_truthy(vim._mock.commands[name])
    vim._mock.commands[name].callback()
  end

  it("primary starts a new hand after hand over", function()
    local started_hand = 0
    match.current_state = match.STATE.HAND_OVER
    match.start_hand = function()
      started_hand = started_hand + 1
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerPrimary")

    assert.are.equal(1, started_hand)
    assert.are.equal(1, renders)
  end)

  it("secondary starts a new hand after hand over", function()
    local started_hand = 0
    match.current_state = match.STATE.HAND_OVER
    match.start_hand = function()
      started_hand = started_hand + 1
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerSecondary")

    assert.are.equal(1, started_hand)
    assert.are.equal(1, renders)
  end)

  it("bet action clamps input and dispatches a raise", function()
    match.current_state = match.STATE.PLAYER_TURN
    match.current_player_index = 1
    match.players = {
      { bet_in_round = 10, stack = 40 },
    }
    match.available_actions = function()
      return { "raise" }
    end
    match.get_state = function()
      return { current_bet = 20, min_raise = 10 }
    end
    local received = {}
    match.player_action = function(action, amount)
      received.action = action
      received.amount = amount
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end
    vim.ui.input = function(opts, cb)
      vim._mock.inputs[#vim._mock.inputs + 1] = opts
      cb("999")
    end

    run_command("PokerBet")

    assert.are.equal("raise", received.action)
    assert.are.equal(50, received.amount)
    assert.are.equal(1, renders)
  end)

  it("notifies when no betting action is available", function()
    match.current_state = match.STATE.PLAYER_TURN
    match.current_player_index = 1
    match.players = { { bet_in_round = 0, stack = 20 } }
    match.available_actions = function()
      return { "check", "call" }
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerBet")

    assert.is_true(#vim._mock.notifications >= 1)
    assert.are.equal(1, renders)
  end)

  it("primary skips ahead during AI turns", function()
    match.current_state = match.STATE.AI_TURN
    local skipped = 0
    match.skip_to_player_turn = function()
      skipped = skipped + 1
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerPrimary")

    assert.are.equal(1, skipped)
    assert.are.equal(1, renders)
  end)

  it("secondary skips ahead during AI turns", function()
    match.current_state = match.STATE.AI_TURN
    local skipped = 0
    match.skip_to_player_turn = function()
      skipped = skipped + 1
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerSecondary")

    assert.are.equal(1, skipped)
    assert.are.equal(1, renders)
  end)

  it("toggles the stats window", function()
    local toggled = 0
    window.toggle_stats = function()
      toggled = toggled + 1
    end

    run_command("PokerStats")

    assert.are.equal(1, toggled)
  end)

  it("resets player stats via the stats command", function()
    local resets = 0
    window.reset_stats = function()
      resets = resets + 1
    end
    local renders = 0
    window.render = function()
      renders = renders + 1
    end

    run_command("PokerResetStats")

    assert.are.equal(1, resets)
    assert.are.equal(1, renders)
  end)
end)
