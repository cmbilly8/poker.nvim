local helper = require("tests.helpers.mock_vim")
helper.setup()

describe("fs adapter", function()
  local fs

  before_each(function()
    package.loaded["poker.fs"] = nil
    fs = require("poker.fs")
  end)

  it("ensures parent directories with vim.fn.mkdir", function()
    local calls = {}
    local original_mkdir = vim.fn.mkdir
    vim.fn.mkdir = function(path, opts)
      calls[#calls + 1] = { path = path, opts = opts }
      return 1
    end

    fs.ensure_parent_dir("/tmp/poker/scores.json")

    vim.fn.mkdir = original_mkdir

    assert.are.same({ { path = "/tmp/poker", opts = "p" } }, calls)
  end)

  it("skips mkdir when no parent directory exists", function()
    local calls = {}
    local original_mkdir = vim.fn.mkdir
    vim.fn.mkdir = function(path, opts)
      calls[#calls + 1] = { path = path, opts = opts }
      return 1
    end

    fs.ensure_parent_dir("scores.json")

    vim.fn.mkdir = original_mkdir

    assert.are.equal(0, #calls)
  end)

  it("writes atomically using a temp file and rename", function()
    local original_open = io.open
    local original_rename = os.rename
    local original_write = fs.write_file
    local opened = {}
    local renamed = {}
    local fallback_called = false

    io.open = function(path, mode)
      opened[#opened + 1] = { path = path, mode = mode }
      return {
        write = function()
        end,
        close = function()
        end,
      }
    end

    os.rename = function(src, dst)
      renamed[#renamed + 1] = { src = src, dst = dst }
      return true
    end

    fs.write_file = function()
      fallback_called = true
    end

    fs.atomic_write("scores.json", "{}")

    io.open = original_open
    os.rename = original_rename
    fs.write_file = original_write

    assert.is_false(fallback_called)
    assert.are.equal(1, #opened)
    assert.are.equal(1, #renamed)
    assert.is_true(opened[1].path:find(".tmp", 1, true) ~= nil)
  end)

  it("falls back to write_file when temp file creation fails", function()
    local original_open = io.open
    local original_write = fs.write_file
    local fallback_called = false
    local fallback_path = nil
    local fallback_contents = nil

    io.open = function()
      return nil
    end

    fs.write_file = function(path, contents)
      fallback_called = true
      fallback_path = path
      fallback_contents = contents
    end

    fs.atomic_write("scores.json", "{\"ok\":true}")

    io.open = original_open
    fs.write_file = original_write

    assert.is_true(fallback_called)
    assert.are.equal("scores.json", fallback_path)
    assert.are.equal("{\"ok\":true}", fallback_contents)
  end)
end)
