local helper = require("tests.helpers.mock_vim")
helper.setup()

local json = require("poker.json")

describe("tuning toolchain", function()
  it("tracks action frequencies per street", function()
    local tracker = require("poker.frequency_tracker")
    tracker.reset()
    tracker.record("preflop", "r")
    tracker.record("preflop", "f")
    tracker.record("preflop", "c")
    tracker.record("flop", "c")
    tracker.record("turn", "r")
    tracker.record("turn", "f")
    tracker.record("river", "c")
    local counts = tracker.export()
    assert.are.same({
      open = 1,
      call = 1,
      fold = 1,
      raise = nil,
      total = 3,
    }, counts.preflop)
    assert.are.same({
      raise = 0,
      call = 1,
      fold = 0,
      total = 1,
    }, counts.flop)
    assert.are.same({
      raise = 1,
      call = 0,
      fold = 1,
      total = 2,
    }, counts.turn)
    assert.are.same({
      raise = 0,
      call = 1,
      fold = 0,
      total = 1,
    }, counts.river)
  end)

  it("computes frequency deltas", function()
    local freq_error = require("poker.frequency_error")
    local observed = {
      preflop = { open = 30, call = 10, total = 40 },
      flop = { raise = 5, fold = 5, total = 20 },
      turn = { raise = 2, fold = 2, total = 4 },
      river = { raise = 0, fold = 1, total = 2 },
    }
    local target = {
      preflop = { open = 0.5, call = 0.5 },
      flop = { raise = 0.2, fold = 0.2 },
      turn = { raise = 0.5, fold = 0.5 },
      river = { raise = 0.25, fold = 0.25 },
    }
    local err = freq_error.compute(observed, target)
    assert.near((30 / 40) - 0.5, err.preflop.open, 1e-6)
    assert.near((10 / 40) - 0.5, err.preflop.call, 1e-6)
    assert.near((5 / 20) - 0.2, err.flop.fold, 1e-6)
    assert.near((5 / 20) - 0.2, err.flop.raise, 1e-6)
    assert.near((2 / 4) - 0.5, err.turn.fold, 1e-6)
    assert.near((2 / 4) - 0.5, err.turn.raise, 1e-6)
    assert.near((1 / 2) - 0.25, err.river.fold, 1e-6)
    assert.near((0 / 2) - 0.25, err.river.raise, 1e-6)
  end)

  it("auto_tune nudges parameters within bounds", function()
    local auto_tune = require("poker.auto_tune")
    local original_params = package.loaded["poker.tuning_params"]
    local original_error = package.loaded["poker.frequency_error"]

    local stub_params = {
      open_raise_freq = 0.10,
      call_freq = 0.20,
      three_bet_value_freq = 0.05,
      three_bet_bluff_freq = 0.02,
      flop_fold_freq = 0.10,
      flop_raise_freq = 0.05,
      flop_call_freq = 0.80,
      turn_fold_freq = 0.10,
      turn_raise_freq = 0.05,
      turn_call_freq = 0.70,
      river_fold_freq = 0.20,
      river_raise_freq = 0.05,
      river_call_freq = 0.70,
      bluff_ratio = 1.0,
      probe_freq = 0.20,
      learning_rate = 0.1,
    }

    package.loaded["poker.tuning_params"] = stub_params
    package.loaded["poker.frequency_error"] = {
      compute = function()
        return {
          preflop = { open = 0.1, call = -0.05 },
          flop = { fold = 0.05, raise = -0.02 },
          turn = { fold = -0.02, raise = 0.03 },
          river = { fold = 0.01, raise = -0.01 },
        }
      end,
    }

    auto_tune.update({}, {})

    assert.near(0.09, stub_params.open_raise_freq, 1e-6)
    assert.near(0.205, stub_params.call_freq, 1e-6)
    assert.near(0.04, stub_params.three_bet_value_freq, 1e-6)
    assert.near(0.025, stub_params.three_bet_bluff_freq, 1e-6)
    assert.near(0.095, stub_params.flop_fold_freq, 1e-6)
    assert.near(0.052, stub_params.flop_raise_freq, 1e-6)
    assert.near(0.803, stub_params.flop_call_freq, 1e-6)
    assert.near(0.102, stub_params.turn_fold_freq, 1e-6)
    assert.near(0.047, stub_params.turn_raise_freq, 1e-6)
    assert.near(0.701, stub_params.turn_call_freq, 1e-6)
    assert.near(0.199, stub_params.river_fold_freq, 1e-6)
    assert.near(0.051, stub_params.river_raise_freq, 1e-6)
    assert.near(0.700, stub_params.river_call_freq, 1e-6)

    package.loaded["poker.tuning_params"] = original_params
    package.loaded["poker.frequency_error"] = original_error
  end)

  it("parse_log script writes observed and analysis outputs", function()
    local tmp = os.tmpname()
    local log = assert(io.open(tmp, "w"))
    log:write("STATE:1:r10r20r45///:xx|xx:\n")
    log:close()

    local writes = {}
    local original_io_open = io.open
    io.open = function(path, mode)
      if mode == "w" then
        local buffer = {}
        return {
          write = function(_, chunk)
            buffer[#buffer + 1] = chunk
          end,
          close = function()
            writes[path] = table.concat(buffer)
          end,
        }
      end
      return original_io_open(path, mode)
    end

    local old_arg = _G.arg
    _G.arg = { tmp }
    local chunk = assert(loadfile("lua/poker/parse_log.lua"))
    local ok, err = pcall(chunk)
    _G.arg = old_arg
    io.open = original_io_open
    os.remove(tmp)
    assert.is_true(ok, err)

    local observed = json.decode(writes["observed_freq.json"])
    local analysis = json.decode(writes["analysis.json"])
    assert.are.equal(1, observed.preflop.open)
    assert.are.equal(1, observed.preflop.total)
    assert.are.equal(1, analysis.preflop.total)
    assert.near(1.0, analysis.preflop.open, 1e-6)
  end)

  it("run_tuner consumes observed data and writes params/history", function()
    local observed = { preflop = { open = 10, call = 0, total = 10 } }
    local observed_json = json.encode(observed)
    local writes = {}
    local original_io_open = io.open
    io.open = function(path, mode)
      if path == "observed_freq.json" and mode == "r" then
        local handle = {}
        function handle:read()
          return observed_json
        end
        function handle:close()
        end
        return handle
      elseif mode == "w" then
        local buffer = {}
        return {
          write = function(_, chunk)
            buffer[#buffer + 1] = chunk
          end,
          close = function()
            writes[path] = table.concat(buffer)
          end,
        }
      end
      return original_io_open(path, mode)
    end

    local original_auto = package.loaded["poker.auto_tune"]
    local original_targets = package.loaded["poker.target_frequencies"]
    package.loaded["poker.auto_tune"] = {
      update = function(obs, targets)
        assert.are.equal(10, obs.preflop.open)
        assert.same({}, targets)
        return { open_raise_freq = 0.5 }
      end,
    }
    package.loaded["poker.target_frequencies"] = {}

    local mkdir_calls = {}
    local original_mkdir = vim.fn.mkdir
    vim.fn.mkdir = function(path, opts)
      mkdir_calls[#mkdir_calls + 1] = { path = path, opts = opts }
      return 1
    end
    local original_getenv = os.getenv
    os.getenv = function(key)
      if key == "TUNER_ITER" then
        return "7"
      end
      return original_getenv(key)
    end

    local chunk = assert(loadfile("lua/poker/run_tuner.lua"))
    local ok, err = pcall(chunk)

    os.getenv = original_getenv
    vim.fn.mkdir = original_mkdir
    package.loaded["poker.auto_tune"] = original_auto
    package.loaded["poker.target_frequencies"] = original_targets
    io.open = original_io_open

    assert.is_true(ok, err)
    assert.are.same({ { path = "tuning_history", opts = "p" } }, mkdir_calls)
    assert.is_truthy(writes["lua/poker/tuning_params.lua"])
    assert.is_truthy(writes["tuning_history/iter_0007.json"])
    assert.are.equal('{"open_raise_freq":0.5}', writes["tuning_history/iter_0007.json"])
    assert.is_true(writes["lua/poker/tuning_params.lua"]:find("open_raise_freq = 0.500000", 1, true) ~= nil)
  end)
end)
