local helper = require("tests.helpers.mock_vim")
helper.setup()

local acpc = require("poker.export.acpc")

local function card(rank, suit)
  return { rank = rank, suit = suit, symbol = tostring(rank), revealed = true }
end

describe("acpc export", function()
  it("serializes gamedef", function()
    local text = acpc.serialize_gamedef({
      small_blind = 10,
      big_blind = 20,
      starting_stack = 1000,
      players = 2,
      first_player = { 1, 1, 1, 1 },
    })
    assert.is_true(text:find("GAMEDEF", 1, true) ~= nil)
    assert.is_true(text:find("numPlayers 2", 1, true) ~= nil)
    assert.is_true(text:find("blind ante 0 10 20", 1, true) ~= nil)
    assert.is_true(text:find("stack 1000", 1, true) ~= nil)
  end)

  it("serializes state lines across streets", function()
    local state = {
      players = {
        { id = 1, name = "P1", is_human = true, hole_cards = { card(14, 3), card(13, 2) } },
        { id = 2, name = "P2", hole_cards = { card(12, 0), card(12, 1) } },
      },
      board = { card(14, 0), card(7, 2), card(2, 1), card(13, 0), card(5, 3) },
      actions = {
        { street = "preflop", action = "blind", amount = 10, total = 10 },
        { street = "preflop", action = "blind", amount = 25, total = 25 },
        { street = "preflop", action = "call", amount = 15, total = 25 },
        { street = "preflop", action = "check", amount = 0, total = 25 },
        { street = "flop", action = "bet", amount = 50, total = 50 },
        { street = "flop", action = "call", amount = 50, total = 50 },
        { street = "turn", action = "check" },
        { street = "turn", action = "check" },
        { street = "river", action = "check" },
        { street = "river", action = "check" },
      },
    }

    local line = acpc.serialize_state(12345, state)
    assert.are.equal("STATE:12345:r10r25cc/r50c/cc/cc:AsKh|xx:Ac7h2dKc5s", line)
  end)

  it("appends to existing log files even when path.exists returns false", function()
    local tmpdir = os.getenv("TMPDIR") or "/tmp"
    local target_path = tmpdir .. "/acpc_write_log_append_test.log"
    os.remove(target_path)

    acpc.write_log(target_path, "FIRST")
    acpc.write_log(target_path, "SECOND")

    local file = io.open(target_path, "r")
    local content = file and file:read("*a") or ""
    if file then
      file:close()
    end
    os.remove(target_path)

    local lines = {}
    for line in string.gmatch(content, "[^\n]+") do
      lines[#lines + 1] = line
    end

    assert.are.same({ "FIRST", "SECOND" }, lines)
  end)

  it("inserts a separator when appending to a file without a trailing newline", function()
    local tmpdir = os.getenv("TMPDIR") or "/tmp"
    local target_path = tmpdir .. "/acpc_write_log_no_newline.log"
    os.remove(target_path)

    local f = io.open(target_path, "w")
    assert.is_truthy(f)
    f:write("FIRST")
    f:close()

    acpc.write_log(target_path, "SECOND")

    local content = {}
    for line in io.lines(target_path) do
      content[#content + 1] = line
    end
    os.remove(target_path)

    assert.are.same({ "FIRST", "SECOND" }, content)
  end)

  it("does not add an extra blank line when file already ends with newline", function()
    local tmpdir = os.getenv("TMPDIR") or "/tmp"
    local target_path = tmpdir .. "/acpc_write_log_with_newline.log"
    os.remove(target_path)

    local f = io.open(target_path, "w")
    assert.is_truthy(f)
    f:write("FIRST\n")
    f:close()

    acpc.write_log(target_path, "SECOND")

    local content = {}
    for line in io.lines(target_path) do
      content[#content + 1] = line
    end
    os.remove(target_path)

    assert.are.same({ "FIRST", "SECOND" }, content)
  end)
end)
