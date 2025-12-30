local helper = require("tests.helpers.mock_vim")
helper.setup()

local simulator = require("poker.simulator")
local acpc = require("poker.export.acpc")
local ai = require("poker.ai")
local match = require("poker.match")

describe("simulator", function()
  local original_write
  local original_rng

  before_each(function()
    original_write = acpc.write_log
    original_rng = ai.set_rng(function()
      return 0.5
    end)
  end)

  after_each(function()
    acpc.write_log = original_write
    ai.set_rng(original_rng)
  end)

  it("plays multiple ai-only hands and logs ACPC states", function()
    local target_path = "/tmp/acpc_sim_test.log"
    local lines = {}
    acpc.write_log = function(path, line)
      if path == target_path then
        lines[#lines + 1] = line
      end
    end

    simulator.run({ hands = 5, players = 3, acpc_path = target_path })

    assert.are.equal(6, #lines)
    assert.is_true(lines[1]:find("GAMEDEF", 1, true) ~= nil)
    assert.is_true(lines[2]:find("STATE:", 1, true) ~= nil)
  end)

  it("disables default export logging during simulation runs", function()
    local target_path = "/tmp/acpc_sim_export_control.log"
    local calls = {}
    acpc.write_log = function(path, line)
      calls[#calls + 1] = { path = path, line = line }
    end

    simulator.run({ hands = 2, players = 2, acpc_path = target_path })

    assert.are.equal(3, #calls)
    for _, entry in ipairs(calls) do
      assert.are.equal(target_path, entry.path)
    end
  end)

  it("does not persist scores during simulation runs", function()
    local fs = require("poker.fs")
    local original_atomic = fs.atomic_write
    local score_writes = 0

    fs.atomic_write = function(path)
      if tostring(path):find("pokerscores", 1, true) then
        score_writes = score_writes + 1
      end
      return true
    end

    simulator.run({ hands = 2, players = 2, acpc_path = "/tmp/acpc_sim_no_persist.log" })

    fs.atomic_write = original_atomic

    assert.are.equal(0, score_writes)
    assert.is_true(match.config.persist_scores ~= false)
  end)

  it("restores config and callbacks after errors", function()
    local original_start_hand = match.start_hand
    local original_config = vim.deepcopy(match.config)
    local original_cb = match.on_hand_complete
    local original_rng = match.get_rng_state()

    local callback = function()
    end
    match.set_on_hand_complete(callback)

    match.set_seed(55)
    local baseline_seed = match.get_rng_state().seed

    match.start_hand = function()
      error("boom")
    end

    local ok = pcall(function()
      simulator.run({ hands = 1, players = 2, acpc_path = "/tmp/acpc_sim_error.log", seed = 99 })
    end)

    assert.is_false(ok)
    assert.are.equal(original_config.ai_opponents, match.config.ai_opponents)
    assert.are.equal(original_config.ai_think_ms, match.config.ai_think_ms)
    assert.are.equal(original_config.small_blind, match.config.small_blind)
    assert.are.equal(original_config.big_blind, match.config.big_blind)
    assert.are.equal(original_config.starting_stack, match.config.starting_stack)
    assert.are.equal(original_config.enable_exports, match.config.enable_exports)
    assert.are.equal(callback, match.on_hand_complete)
    assert.are.equal(baseline_seed, match.get_rng_state().seed)

    match.start_hand = original_start_hand
    match.set_on_hand_complete(original_cb)
    match.restore_rng(original_rng)
  end)

  it("applies the provided rng seed", function()
    local target_path = "/tmp/acpc_sim_seed.log"
    local original_set_seed = match.set_seed
    local seen = {}
    match.set_seed = function(seed)
      seen.seed = seed
      return original_set_seed(seed)
    end

    simulator.run({ hands = 1, players = 2, acpc_path = target_path, seed = 42 })

    match.set_seed = original_set_seed

    assert.are.equal(42, seen.seed)
  end)

  it("restarts the table when only one player remains", function()
    local target_path = "/tmp/acpc_sim_restart.log"
    local calls = {}
    acpc.write_log = function(path, line)
      calls[#calls + 1] = { path = path, line = line }
    end

    local cards = require("poker.cards")
    local original_new_shuffled = cards.new_shuffled
    local deck1 = {
      { rank = 4, suit = 0 },
      { rank = 5, suit = 1 },
      { rank = 6, suit = 2 },
      { rank = 7, suit = 3 },
      { rank = 8, suit = 0 },
      { rank = 2, suit = 1 },
      { rank = 14, suit = 1 },
      { rank = 3, suit = 0 },
      { rank = 14, suit = 2 },
    }
    local deck2 = vim.deepcopy(deck1)
    local deck_index = 1
    cards.new_shuffled = function()
      local deck = deck_index == 1 and deck1 or deck2
      deck_index = deck_index + 1
      return vim.deepcopy(deck)
    end

    simulator.run({
      hands = 2,
      players = 2,
      acpc_path = target_path,
      starting_stack = 1,
      small_blind = 1,
      big_blind = 1,
    })

    cards.new_shuffled = original_new_shuffled

    assert.are.equal(3, #calls)
    assert.is_true(calls[2].line:find("STATE:1:", 1, true) ~= nil)
    assert.is_true(calls[3].line:find("STATE:2:", 1, true) ~= nil)
  end)

  it("writes default logs to timestamped files under data/sim", function()
    local tmpdir = os.getenv("TMPDIR") or "/tmp"
    local data_dir = tmpdir .. "/poker-sim-default"
    local previous_data_dir = match.data_dir
    match.data_dir = data_dir

    local original_time = os.time
    local base_time = 1700000000
    local first_target = string.format("%s/sim/acpc_sim_%d.log", data_dir, base_time)
    local second_target = string.format("%s/sim/acpc_sim_%d.log", data_dir, base_time + 1)

    os.remove(first_target)
    os.remove(second_target)

    os.time = function()
      return base_time
    end

    local first_path = simulator.run({ hands = 1, players = 2 })

    os.time = function()
      return base_time + 1
    end
    local second_path = simulator.run({ hands = 1, players = 2 })

    os.time = original_time
    match.data_dir = previous_data_dir

    assert.is_truthy(first_path)
    assert.is_truthy(second_path)
    assert.are.equal(first_target, first_path)
    assert.are.equal(second_target, second_path)
    assert.are_not.equal(first_path, second_path)

    local function read_lines(path)
      local results = {}
      local file = io.open(path, "r")
      assert.is_truthy(file)
      for line in file:lines() do
        results[#results + 1] = line
      end
      file:close()
      return results
    end

    local first_lines = read_lines(first_path)
    local second_lines = read_lines(second_path)

    os.remove(first_path)
    os.remove(second_path)

    local function state_count(lines)
      local count = 0
      for _, line in ipairs(lines) do
        if line:find("STATE:", 1, true) == 1 then
          count = count + 1
        end
      end
      return count
    end

    assert.are.equal(1, state_count(first_lines))
    assert.are.equal(1, state_count(second_lines))
  end)
end)
