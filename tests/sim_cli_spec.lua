local helper = require("tests.helpers.mock_vim")
helper.setup()

local sim_cli = require("poker.sim_cli")

describe("sim cli", function()
  it("parses defaults", function()
    local opts = assert(sim_cli.parse_args({}))
    assert.are.equal(10000, opts.hands)
    assert.are.equal(7, opts.players)
    assert.is_nil(opts.acpc_path)
  end)

  it("parses explicit arguments", function()
    local opts = assert(sim_cli.parse_args({
      "--hands",
      "5",
      "--players=3",
      "--acpc-path",
      "out.log",
    }))
    assert.are.equal(5, opts.hands)
    assert.are.equal(3, opts.players)
    assert.are.equal("out.log", opts.acpc_path)
  end)

  it("reports missing values", function()
    local opts, err = sim_cli.parse_args({ "--hands" })
    assert.is_nil(opts)
    assert.is_true(err:find("Missing value", 1, true) ~= nil)
  end)

  it("runs the simulator with parsed options", function()
    local original_sim = package.loaded["poker.simulator"]
    local captured = {}

    package.loaded["poker.simulator"] = {
      run = function(opts)
        captured.opts = opts
        return "/tmp/acpc.log"
      end,
    }

    local ok = sim_cli.run({ "--hands", "2", "--players", "4" })

    package.loaded["poker.simulator"] = original_sim

    assert.is_true(ok)
    assert.are.equal(2, captured.opts.hands)
    assert.are.equal(4, captured.opts.players)
    assert.is_nil(captured.opts.acpc_path)
  end)
end)
