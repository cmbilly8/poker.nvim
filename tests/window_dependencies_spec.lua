local helper = require("tests.helpers.mock_vim")
helper.setup()

describe("window dependency handling", function()
  before_each(function()
    vim._mock.reset()
    package.loaded["poker.window"] = nil
    package.loaded["plenary.popup"] = nil
    package.preload["plenary.popup"] = function()
      error("plenary missing")
    end
  end)

  after_each(function()
    package.loaded["poker.window"] = nil
    package.preload["plenary.popup"] = nil
  end)

  it("notifies the user when plenary is missing", function()
    local window = require("poker.window")
    assert.has_no.errors(function()
      window.open_table()
    end)
    local notification = vim._mock.notifications[1]
    assert.is_not_nil(notification)
    assert.matches("plenary", string.lower(notification.msg or ""))
    assert.equals(vim.log.levels.ERROR, notification.level)
  end)
end)
