local helper = require("tests.helpers.mock_vim")
helper.setup()

local match = require("poker.match")
local acpc = require("poker.export.acpc")
local ps = require("poker.export.pokerstars")

local function wait_for_player_turn()
  local guard = 0
  while match.current_state ~= match.STATE.PLAYER_TURN do
    if match.current_state == match.STATE.AI_TURN and vim._mock.run_deferred then
      vim._mock.run_deferred()
    else
      match.progress()
    end
    guard = guard + 1
    if guard > 100 then
      error("player turn not reached")
    end
  end
end

local function wait_for_hand_over()
  local guard = 0
  while match.current_state ~= match.STATE.HAND_OVER do
    if match.current_state == match.STATE.AI_TURN and vim._mock.run_deferred then
      vim._mock.run_deferred()
    else
      match.progress()
    end
    guard = guard + 1
    if guard > 200 then
      error("hand did not finish")
    end
  end
end

local function play_fold_hand()
  match.config.ai_opponents = 1
  match.config.ai_think_ms = 0
  match.start_session()
  match.start_hand()
  wait_for_player_turn()
  match.player_action("fold")
  wait_for_hand_over()
end

describe("export configuration", function()
  local original_config
  local original_acpc_write
  local original_ps_write

  before_each(function()
    original_config = vim.deepcopy(match.config)
    original_acpc_write = acpc.write_log
    original_ps_write = ps.write_hand
  end)

  after_each(function()
    for key, value in pairs(original_config) do
      match.config[key] = value
    end
    acpc.write_log = original_acpc_write
    ps.write_hand = original_ps_write
  end)

  it("skips exporter writes when enable_exports is false", function()
    local acpc_calls = 0
    local ps_calls = 0
    acpc.write_log = function()
      acpc_calls = acpc_calls + 1
    end
    ps.write_hand = function()
      ps_calls = ps_calls + 1
    end

    match.configure({
      enable_exports = false,
      export_acpc_path = "/tmp/poker_acpc_disabled.log",
      export_pokerstars_dir = "/tmp/poker_ps_disabled",
    })

    play_fold_hand()

    assert.are.equal(0, acpc_calls)
    assert.are.equal(0, ps_calls)
  end)

  it("writes PokerStars logs with the configured table name", function()
    local ps_output
    local acpc_lines = {}
    acpc.write_log = function(_, line)
      acpc_lines[#acpc_lines + 1] = line
    end
    ps.write_hand = function(_, text)
      ps_output = text
    end

    match.configure({
      enable_exports = true,
      export_acpc_path = "/tmp/poker_acpc_config.log",
      export_pokerstars_dir = "/tmp/poker_ps_config",
      table_name = "ConfigSpec Table",
    })

    play_fold_hand()

    assert.is_true(#acpc_lines > 0)
    assert.is_not_nil(ps_output)
    assert.is_not_nil(ps_output:find("ConfigSpec Table", 1, true))
  end)
end)
