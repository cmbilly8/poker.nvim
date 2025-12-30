local helper = require("tests.helpers.mock_vim")
helper.setup()

local batch_cli = require("poker.batch_cli")

describe("batch cli", function()
  it("parses defaults", function()
    local opts = assert(batch_cli.parse_args({}))
    assert.are.equal(20, opts.iterations)
    assert.are.equal(10000, opts.hands)
    assert.are.equal(7, opts.players)
    assert.are.equal("tmp_acpc.log", opts.acpc_path)
  end)

  it("parses explicit arguments", function()
    local opts = assert(batch_cli.parse_args({
      "--iterations",
      "3",
      "--hands=25",
      "--players",
      "4",
      "--acpc-path",
      "custom.log",
    }))
    assert.are.equal(3, opts.iterations)
    assert.are.equal(25, opts.hands)
    assert.are.equal(4, opts.players)
    assert.are.equal("custom.log", opts.acpc_path)
  end)

  it("uses the simulator when no acpc_match is executable", function()
    local original_execute = os.execute
    local original_sim = package.loaded["poker.simulator"]
    local commands = {}
    local captured = {}

    os.execute = function(cmd)
      commands[#commands + 1] = cmd
      if cmd:find("acpc_match", 1, true) and cmd:find("-x", 1, true) then
        return 1
      end
      return 0
    end

    package.loaded["poker.simulator"] = {
      run = function(opts)
        captured.opts = opts
        return "/tmp/acpc.log"
      end,
    }

    local ok = batch_cli.run({
      "--iterations",
      "1",
      "--hands",
      "5",
      "--players",
      "3",
      "--acpc-path",
      "batch.log",
    })

    os.execute = original_execute
    package.loaded["poker.simulator"] = original_sim

    assert.is_true(ok)
    assert.are.equal(5, captured.opts.hands)
    assert.are.equal(3, captured.opts.players)
    assert.are.equal("batch.log", captured.opts.acpc_path)
    local joined = table.concat(commands, "\n")
    assert.is_true(joined:find("parse_log.lua", 1, true) ~= nil)
    assert.is_true(joined:find("run_tuner.lua", 1, true) ~= nil)
  end)
end)
