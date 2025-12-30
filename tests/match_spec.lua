local helper = require("tests.helpers.mock_vim")
helper.setup()

local match = require("poker.match")
local ai = require("poker.ai")

local function wait_for_player_turn()
  local guard = 0
  while match.current_state ~= match.STATE.PLAYER_TURN and match.current_state ~= match.STATE.HAND_OVER do
    if vim._mock.run_deferred then
      vim._mock.run_deferred()
    end
    match.progress()
    guard = guard + 1
    if guard > 50 then
      error("progress did not yield player turn")
    end
  end
end

local function setup_table(opts)
  match.config.starting_stack = opts.starting_stack or 100
  match.config.small_blind = opts.small_blind or 5
  match.config.big_blind = opts.big_blind or 10
  match.config.ai_opponents = opts.ai_opponents or 1
  match.config.ai_think_ms = opts.ai_think_ms or 0
  match.start_session()
  match.start_hand()
  wait_for_player_turn()
end

describe("match flow", function()
  before_each(function()
    ai.decide = function()
      return "check"
    end
    match.set_on_change(nil)
  end)

  it("posts blinds and deals two cards per player", function()
    setup_table({ ai_opponents = 1, starting_stack = 100, small_blind = 5, big_blind = 10 })
    assert.are.equal(2, #match.players)
    assert.are.equal(2, #match.players[1].hole_cards)
    assert.are.equal(2, #match.players[2].hole_cards)
    local sb = match.players[match.small_blind_index]
    assert.are.equal(5, sb.bet_in_round)
    local bb = match.players[match.big_blind_index]
    assert.are.equal(10, bb.bet_in_round)
    assert.are.equal(15, match.pot)
  end)

  it("ends the hand and awards pot when the player folds", function()
    setup_table({ ai_opponents = 1 })
    local starting_ai = match.players[2].stack
    match.player_action("fold")
    wait_for_player_turn()
    assert.are.equal(match.STATE.HAND_OVER, match.current_state)
    assert.is_true(match.players[1].folded)
    assert.is_true(match.players[2].stack > starting_ai)
  end)

  it("removes busted opponents before the next hand", function()
    ai.decide = function()
      return "fold"
    end
    setup_table({ ai_opponents = 1 })
    match.players[2].stack = 0
    match.player_action("check")
    wait_for_player_turn()
    assert.is_not_nil(next(match.pending_opponent_removals))
    local total_players = #match.players
    match.start_hand()
    wait_for_player_turn()
    assert.are.equal(total_players - 1, #match.players)
  end)

  it("forces a restart when the player busts", function()
    setup_table({ ai_opponents = 1 })
    match.players[1].stack = 0
    match.player_action("fold")
    wait_for_player_turn()
    assert.is_true(match.awaiting_restart)
    match.start_hand()
    wait_for_player_turn()
    assert.is_false(match.awaiting_restart)
    assert.are.equal(match.config.ai_opponents + 1, #match.players)
  end)

  it("delays AI decisions using the configured think time", function()
    ai.decide = function()
      return "check"
    end
    setup_table({ ai_opponents = 1, ai_think_ms = 25 })
    match.player_action("call")

    assert.are.equal(match.STATE.AI_TURN, match.current_state)
    assert.are.equal(1, #vim._mock.deferred)
    assert.are.equal(25, vim._mock.deferred[1].timeout)
    assert.is_true(match.players[2].last_action:find("posts big blind", 1, true) ~= nil)

    vim._mock.run_deferred()
    wait_for_player_turn()
    assert.is_true(vim.tbl_contains(match.last_events, "Michael checks"))
    assert.are.equal(match.STATE.PLAYER_TURN, match.current_state)
  end)

  it("renders changes after deferred AI actions", function()
    local renders = 0
    local states = {}
    match.set_on_change(function()
      renders = renders + 1
      states[#states + 1] = match.current_state
    end)
    setup_table({ ai_opponents = 1, ai_think_ms = 10 })
    renders = 0

    match.player_action("call")
    assert.is_true(match.waiting_on_ai)
    vim._mock.run_deferred()
    wait_for_player_turn()

    assert.is_true(renders > 0)
    assert.is_true(vim.tbl_contains(states, match.STATE.PLAYER_TURN))
  end)

  it("fast forwards AI actions when skipping to the player turn", function()
    ai.decide = function()
      return "check"
    end
    setup_table({ ai_opponents = 2, ai_think_ms = 40 })
    match.player_action("call")
    assert.is_true(match.waiting_on_ai)
    match.skip_to_player_turn()
    assert.is_false(match.waiting_on_ai)
    wait_for_player_turn()
    assert.are.equal(match.STATE.PLAYER_TURN, match.current_state)
    assert.are.equal(1, match.current_player_index)
  end)

  it("naturally completes a hand after the last AI timer", function()
    ai.decide = function()
      return "check"
    end
    match.config.ai_think_ms = 5
    match.config.ai_opponents = 1
    match.start_session()
    match.start_hand()
    local guard = 0
    while match.current_state ~= match.STATE.HAND_OVER do
      if match.current_state == match.STATE.PLAYER_TURN then
        local actions = match.available_actions(match.players[1])
        if vim.tbl_contains(actions, "check") then
          match.player_action("check")
        else
          match.player_action("call")
        end
      elseif match.current_state == match.STATE.AI_TURN then
        vim._mock.run_deferred()
      else
        match.progress()
      end
      guard = guard + 1
      if guard > 200 then
        error("hand did not finish naturally")
      end
    end
    assert.is_false(match.waiting_on_ai)
  end)

  it("prevents free folds when nothing to call", function()
    ai.decide = function()
      return "fold"
    end
    setup_table({ ai_opponents = 1, ai_think_ms = 0 })
    -- Player checks, AI tries to fold with zero to call, should check instead.
    match.player_action("check")
    vim._mock.run_deferred()
    wait_for_player_turn()
    assert.are.equal(match.STATE.PLAYER_TURN, match.current_state)
    assert.is_false(match.players[2].folded)
  end)

  it("feeds opponent model with actions and showdown outcomes", function()
    local opponent_model = require("poker.ai.opponent_model")
    local recorded_actions = {}
    local recorded_showdowns = {}
    local original_action = opponent_model.record_action
    local original_showdown = opponent_model.record_showdown

    opponent_model.record_action = function(id, action, amount, street)
      recorded_actions[#recorded_actions + 1] = { id = id, action = action, street = street, amount = amount }
    end
    opponent_model.record_showdown = function(id, won, saw_showdown)
      recorded_showdowns[#recorded_showdowns + 1] = { id = id, won = won, saw = saw_showdown }
    end

    setup_table({ ai_opponents = 1, starting_stack = 100, small_blind = 5, big_blind = 10 })
    match.player_action("call")
    while match.current_state ~= match.STATE.HAND_OVER do
      if match.current_state == match.STATE.PLAYER_TURN then
        match.player_action("check")
      else
        match.progress()
      end
    end

    opponent_model.record_action = original_action
    opponent_model.record_showdown = original_showdown

    assert.is_true(#recorded_actions > 0)
    assert.are.equal(#match.players, #recorded_showdowns)
    local saw = 0
    for _, entry in ipairs(recorded_showdowns) do
      if entry.saw then
        saw = saw + 1
      end
    end
    assert.is_true(saw >= 1)
  end)

  it("resets opponent model on start_session", function()
    local opponent_model = require("poker.ai.opponent_model")

    opponent_model.record_action(1, "raise", 20, "preflop")
    local before = opponent_model.get_stats(1)
    assert.is_true(before.vpip > 0)

    match.start_session()

    local after = opponent_model.get_stats(1)
    assert.are.equal(0, after.vpip)
    assert.are.equal(0, after.pfr)
  end)

  it("uses correct grammar when the player wins a showdown", function()
    setup_table({ ai_opponents = 1 })
    local player = match.players[1]
    local opponent = match.players[2]
    local function card(rank, suit, symbol)
      return { rank = rank, suit = suit, symbol = symbol, revealed = true }
    end

    player.hole_cards = { card(14, 0, "A"), card(13, 1, "K") }
    opponent.hole_cards = { card(9, 2, "9"), card(8, 3, "8") }
    player.folded = false
    opponent.folded = false
    match.board = {
      card(2, 0, "2"),
      card(5, 1, "5"),
      card(7, 2, "7"),
      card(11, 3, "J"),
      card(4, 0, "4"),
    }
    match.pot = 120
    player.total_contribution = 60
    opponent.total_contribution = 60
    player.stack = match.config.starting_stack - 60
    opponent.stack = match.config.starting_stack - 60
    match.current_state = match.STATE.SHOWDOWN
    match.last_events = {}

    match.progress()

    assert.are.equal("You win 120 chips", match.last_events[1])
  end)

  it("exposes position and blind metadata in get_state", function()
    setup_table({ ai_opponents = 2, starting_stack = 500, small_blind = 5, big_blind = 10, ai_think_ms = 50 })
    match.button_index = #match.players
    match.start_hand()
    wait_for_player_turn()
    local hero = match.players[1]
    local initial_state = match.get_state(hero)

    assert.are.equal(1, initial_state.seat)
    assert.are.equal("BTN", initial_state.position)
    assert.are.equal(10, initial_state.big_blind)
    assert.are.equal(5, initial_state.small_blind)
    assert.are.equal(0, initial_state.preflop_raise_count)
    assert.is_false(initial_state.has_raised)
    assert.are.equal(1, initial_state.players[1].seat)
    assert.is_true(initial_state.players[1].position ~= nil)

    match.player_action("raise", 40)

    local after_state = match.get_state(hero)
    assert.is_true(after_state.has_raised)
    assert.is_true(after_state.preflop_raise_count >= 1)
    assert.are.equal("BTN", after_state.position)

    while #vim._mock.deferred > 0 do
      vim._mock.run_deferred()
    end
  end)

  it("awards side pots according to each player's contribution", function()
    setup_table({ ai_opponents = 2, starting_stack = 500, small_blind = 5, big_blind = 10 })
    local function card(rank, suit)
      return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
    end

    local players = match.players
    match.board = {
      card(2, 0),
      card(3, 0),
      card(4, 0),
      card(9, 1),
      card(11, 2),
    }
    players[1].hole_cards = { card(14, 0), card(10, 0) } -- nut flush
    players[2].hole_cards = { card(13, 3), card(13, 1) } -- pair of kings
    players[3].hole_cards = { card(8, 2), card(7, 1) } -- high card

    local contributions = { 50, 200, 200 }
    for idx, amount in ipairs(contributions) do
      local player = players[idx]
      player.folded = false
      player.total_contribution = amount
      player.bet_in_round = 0
      player.stack = match.config.starting_stack - amount
      player.all_in = player.stack <= 0
      player.last_action = nil
    end

    match.pot = 450
    match.current_state = match.STATE.SHOWDOWN

    match.progress()

    assert.are.equal(match.STATE.HAND_OVER, match.current_state)
    assert.are.equal(match.config.starting_stack - contributions[1] + 150, players[1].stack)
    assert.are.equal(match.config.starting_stack - contributions[2] + 300, players[2].stack)
    assert.are.equal(match.config.starting_stack - contributions[3], players[3].stack)
    assert.is_true(vim.tbl_contains(match.last_events, "You win 150 chips"))
    assert.is_true(vim.tbl_contains(match.last_events, "Michael wins 300 chips"))

    assert.are.same({ "You win 150 chips", "Michael wins 300 chips" }, match.showdown.payouts)
    local payout_lookup = {}
    for _, entry in ipairs(match.showdown.winners) do
      payout_lookup[entry.player.name] = entry.amount
    end
    assert.are.equal(150, payout_lookup["You"])
    assert.are.equal(300, payout_lookup["Michael"])
  end)

  it("uses seeded rng for deterministic shuffles", function()
    match.config.ai_opponents = 1
    match.config.ai_think_ms = 0

    match.set_seed(123)
    match.start_session()
    match.start_hand()
    local first = match.get_my_cards()

    local function signature(cards)
      local parts = {}
      for _, card in ipairs(cards or {}) do
        parts[#parts + 1] = string.format("%s-%s", tostring(card.rank), tostring(card.suit))
      end
      return table.concat(parts, ",")
    end

    local first_sig = signature(first)

    match.set_seed(123)
    match.start_session()
    match.start_hand()
    local second_sig = signature(match.get_my_cards())

    assert.are.equal(first_sig, second_sig)

    match.set_seed(124)
    match.start_session()
    match.start_hand()
    local third_sig = signature(match.get_my_cards())

    assert.are_not.equal(first_sig, third_sig)
  end)
end)

describe("match configuration", function()
  local original_config
  local original_tracker

  before_each(function()
    original_config = vim.deepcopy(match.config)
    original_tracker = match.stats.tracker
  end)

  after_each(function()
    for key, value in pairs(original_config) do
      match.config[key] = value
    end
    match.min_raise = match.config.big_blind
    match.stats.tracker = original_tracker
  end)

  it("applies valid overrides", function()
    match.configure({
      starting_stack = 1500,
      small_blind = 15,
      big_blind = 30,
      ai_opponents = 3,
      ai_think_ms = 250,
      enable_exports = true,
      export_acpc_path = "/tmp/acpc.log",
      export_pokerstars_dir = "/tmp/pokerstars",
      scores_path = "/tmp/poker_scores.json",
      table_name = "Test Table",
    })

    assert.are.equal(1500, match.config.starting_stack)
    assert.are.equal(15, match.config.small_blind)
    assert.are.equal(30, match.config.big_blind)
    assert.are.equal(30, match.min_raise)
    assert.are.equal(3, match.config.ai_opponents)
    assert.are.equal(250, match.config.ai_think_ms)
    assert.is_true(match.config.enable_exports)
    assert.are.equal("/tmp/poker_scores.json", match.config.scores_path)
    assert.are.equal("Test Table", match.config.table_name)
    assert.are.equal("/tmp/acpc.log", match.config.export_acpc_path)
    assert.are.equal("/tmp/pokerstars", match.config.export_pokerstars_dir)
  end)

  it("rejects invalid options without mutating config", function()
    match.configure({
      starting_stack = -1,
      small_blind = 0,
      big_blind = "abc",
      ai_opponents = 0,
      ai_think_ms = -50,
      scores_path = "",
      table_name = "",
      export_acpc_path = "",
      export_pokerstars_dir = 0,
      persist_scores = "nope",
    })

    assert.are.equal(original_config.starting_stack, match.config.starting_stack)
    assert.are.equal(original_config.small_blind, match.config.small_blind)
    assert.are.equal(original_config.big_blind, match.config.big_blind)
    assert.are.equal(original_config.ai_opponents, match.config.ai_opponents)
    assert.are.equal(original_config.ai_think_ms, match.config.ai_think_ms)
    assert.are.equal(original_config.scores_path, match.config.scores_path)
    assert.are.equal(original_config.table_name, match.config.table_name)
    assert.are.equal(original_config.export_acpc_path, match.config.export_acpc_path)
    assert.are.equal(original_config.export_pokerstars_dir, match.config.export_pokerstars_dir)
    assert.are.equal(original_config.persist_scores, match.config.persist_scores)
    assert.are.equal(original_config.big_blind, match.min_raise)
  end)

  it("accepts persistence overrides", function()
    match.configure({ persist_scores = false })
    assert.is_false(match.config.persist_scores)
    match.configure({ persist_scores = true })
    assert.is_true(match.config.persist_scores)
  end)

  it("resets tracked player stats without touching scores", function()
    match.stats.hands_played = 3
    match.stats.player_wins = 2
    match.stats.tracker = { players = { [1] = { hands = 5 } } }

    match.reset_stats()

    assert.are.equal(3, match.stats.hands_played)
    assert.are.equal(2, match.stats.player_wins)
    assert.is_true(match.stats.tracker ~= nil)
    assert.is_true(next(match.stats.tracker.players or {}) == nil)
  end)
end)

describe("score persistence", function()
  local fs
  local original_read
  local original_atomic
  local original_decode
  local original_fn_decode
  local original_encode
  local original_persist
  local original_stats

  before_each(function()
    fs = require("poker.fs")
    original_read = fs.read_file
    original_atomic = fs.atomic_write
    original_decode = vim.json.decode
    original_fn_decode = vim.fn.json_decode
    original_encode = vim.fn.json_encode
    original_persist = match.config.persist_scores
    original_stats = {
      hands_played = match.stats.hands_played,
      player_wins = match.stats.player_wins,
      player_losses = match.stats.player_losses,
      player_ties = match.stats.player_ties,
      tracker = match.stats.tracker,
    }
    match.config.persist_scores = true
  end)

  after_each(function()
    fs.read_file = original_read
    fs.atomic_write = original_atomic
    vim.json.decode = original_decode
    vim.fn.json_decode = original_fn_decode
    vim.fn.json_encode = original_encode
    match.config.persist_scores = original_persist
    match.stats.hands_played = original_stats.hands_played
    match.stats.player_wins = original_stats.player_wins
    match.stats.player_losses = original_stats.player_losses
    match.stats.player_ties = original_stats.player_ties
    match.stats.tracker = original_stats.tracker
  end)

  it("migrates legacy score payloads", function()
    local json = require("poker.json")
    local payload = {
      hands_played = 7,
      player_wins = 3,
      player_losses = 2,
      player_ties = 1,
      tracker = { players = { { hands = 4 } } },
    }
    local encoded = json.encode(payload)
    vim.json.decode = json.decode
    fs.read_file = function()
      return encoded
    end

    match.stats.hands_played = 0
    match.stats.player_wins = 0
    match.stats.player_losses = 0
    match.stats.player_ties = 0
    match.stats.tracker = { players = {} }

    match.start_session()

    assert.are.equal(7, match.stats.hands_played)
    assert.are.equal(3, match.stats.player_wins)
    assert.are.equal(2, match.stats.player_losses)
    assert.are.equal(1, match.stats.player_ties)
    assert.is_true(type(match.stats.tracker.players) == "table")
  end)

  it("validates versioned score payloads", function()
    local json = require("poker.json")
    local payload = {
      schema_version = 1,
      stats = {
        hands_played = "nope",
        player_wins = 4,
        player_losses = -1,
        player_ties = 2,
        tracker = "bad",
      },
    }
    local encoded = json.encode(payload)
    vim.json.decode = json.decode
    fs.read_file = function()
      return encoded
    end

    match.stats.hands_played = 0
    match.stats.player_wins = 0
    match.stats.player_losses = 0
    match.stats.player_ties = 0
    match.stats.tracker = { players = {} }

    match.start_session()

    assert.are.equal(0, match.stats.hands_played)
    assert.are.equal(4, match.stats.player_wins)
    assert.are.equal(0, match.stats.player_losses)
    assert.are.equal(2, match.stats.player_ties)
    assert.is_true(type(match.stats.tracker.players) == "table")
    assert.is_true(next(match.stats.tracker.players) == nil)
  end)

  it("ignores corrupted score payloads", function()
    vim.json.decode = function()
      error("bad json")
    end
    fs.read_file = function()
      return "{"
    end

    match.stats.hands_played = 0
    match.stats.player_wins = 0
    match.stats.player_losses = 0
    match.stats.player_ties = 0
    match.stats.tracker = { players = {} }

    match.start_session()

    assert.are.equal(0, match.stats.hands_played)
    assert.are.equal(0, match.stats.player_wins)
    assert.is_true(type(match.stats.tracker.players) == "table")
  end)

  it("falls back to vim.fn.json_decode when vim.json.decode is unavailable", function()
    local json = require("poker.json")
    local payload = {
      schema_version = 1,
      stats = {
        hands_played = 5,
        player_wins = 2,
        player_losses = 1,
        player_ties = 0,
        tracker = { players = { { hands = 3 } } },
      },
    }
    local encoded = json.encode(payload)
    vim.json.decode = nil
    vim.fn.json_decode = json.decode
    fs.read_file = function()
      return encoded
    end

    match.stats.hands_played = 0
    match.stats.player_wins = 0
    match.stats.player_losses = 0
    match.stats.player_ties = 0
    match.stats.tracker = { players = {} }

    match.start_session()

    assert.are.equal(5, match.stats.hands_played)
    assert.are.equal(2, match.stats.player_wins)
    assert.are.equal(1, match.stats.player_losses)
    assert.are.equal(0, match.stats.player_ties)
    assert.is_true(type(match.stats.tracker.players) == "table")
  end)

  it("writes scores with schema metadata", function()
    local json = require("poker.json")
    local written = nil
    vim.fn.json_encode = json.encode

    fs.atomic_write = function(_, contents)
      written = contents
      return true
    end

    match.reset_scores()

    local decoded = json.decode(written or "{}")
    assert.are.equal(1, decoded.schema_version)
    assert.is_true(type(decoded.stats) == "table")
    assert.is_true(decoded.stats.hands_played ~= nil)
  end)
end)
