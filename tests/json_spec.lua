local helper = require("tests.helpers.mock_vim")
helper.setup()

describe("json fallback", function()
  local original_decode
  local original_fn_decode
  local original_cjson_loaded
  local original_dkjson_loaded
  local original_cjson_preload
  local original_dkjson_preload
  local original_json_loaded

  before_each(function()
    original_decode = vim.json.decode
    original_fn_decode = vim.fn.json_decode
    original_cjson_loaded = package.loaded["cjson"]
    original_dkjson_loaded = package.loaded["dkjson"]
    original_cjson_preload = package.preload["cjson"]
    original_dkjson_preload = package.preload["dkjson"]
    original_json_loaded = package.loaded["poker.json"]
  end)

  after_each(function()
    vim.json.decode = original_decode
    vim.fn.json_decode = original_fn_decode
    package.loaded["cjson"] = original_cjson_loaded
    package.loaded["dkjson"] = original_dkjson_loaded
    package.preload["cjson"] = original_cjson_preload
    package.preload["dkjson"] = original_dkjson_preload
    package.loaded["poker.json"] = original_json_loaded
  end)

  local function load_fallback_json()
    package.loaded["cjson"] = nil
    package.loaded["dkjson"] = nil
    package.preload["cjson"] = function()
      error("cjson disabled")
    end
    package.preload["dkjson"] = function()
      error("dkjson disabled")
    end
    package.loaded["poker.json"] = nil
    return require("poker.json")
  end

  it("decodes objects and arrays when vim decoders are unavailable", function()
    local json = load_fallback_json()
    vim.json.decode = nil
    vim.fn.json_decode = nil

    local decoded = json.decode("{\"a\":1,\"b\":[2,3],\"c\":{\"d\":\"hi\\n\"}}")

    assert.are.equal(1, decoded.a)
    assert.are.equal(2, decoded.b[1])
    assert.are.equal(3, decoded.b[2])
    assert.are.equal("hi\n", decoded.c.d)
  end)

  it("errors on invalid json", function()
    local json = load_fallback_json()
    vim.json.decode = nil
    vim.fn.json_decode = nil

    assert.has_error(function()
      json.decode("{\"a\":}")
    end)
  end)
end)
