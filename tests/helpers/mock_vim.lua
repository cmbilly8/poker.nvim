local M = {}

local function deepcopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  if seen and seen[value] then
    return seen[value]
  end
  local copy = {}
  seen = seen or {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepcopy(k, seen)] = deepcopy(v, seen)
  end
  return copy
end

local function repo_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  local helpers_dir = source:match("(.*/)") or "./"
  local root = helpers_dir .. "../.."
  return root
end

local function extend_package_path()
  local root = repo_root()
  local lua_dir = root .. "/lua"
  local template = table.concat({
    lua_dir .. "/?.lua",
    lua_dir .. "/?/init.lua",
    root .. "/?.lua",
    root .. "/?/init.lua",
    "%s",
  }, ";")
  package.path = string.format(template, package.path)
end

local function ensure_plenary_stub()
  if package.loaded["plenary.path"] then
    return
  end

  package.preload["plenary.path"] = function()
    local Path = {}
    Path.__index = Path

    function Path:new(path_str)
      return setmetatable({ _path = path_str }, Path)
    end

    function Path:parent()
      return self
    end

    function Path:exists()
      return false
    end

    function Path:mkdir(_opts)
    end

    function Path:write(_contents, _mode)
    end

    function Path:read()
      return "{}"
    end

    return Path
  end
end

local function trim(text)
  if text == nil then
    return ""
  end
  local trimmed = text:match("^%s*(.-)%s*$")
  if trimmed == nil then
    return ""
  end
  return trimmed
end

local function utf8_chars(text)
  text = tostring(text or "")
  return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function strdisplaywidth(text)
  if text == nil then
    return 0
  end
  local width = 0
  for char in utf8_chars(text) do
    if char == "\t" then
      width = width + 1
    else
      width = width + 1
    end
  end
  return width
end

local function split(text, pattern)
  text = text or ""
  if pattern == [[\zs]] then
    local chars = {}
    for char in utf8_chars(text) do
      chars[#chars + 1] = char
    end
    return chars
  end
  local results = {}
  for token in string.gmatch(text, "[^" .. pattern .. "]+") do
    results[#results + 1] = token
  end
  return results
end

local function reset_mock_state(mock)
  mock.buffers = {}
  mock.windows = {}
  mock.highlights = {}
  mock.namespaces = {}
  mock.highlight_defs = {}
  mock.commands = {}
  mock.notifications = {}
  mock.inputs = {}
  mock.keymaps = {}
  mock.deferred = {}
  mock.autocmds = {}
  mock.augroups = {}
  mock.next_buf = 1
  mock.next_win = 1
  mock.next_ns = 1
  mock.next_aucmd = 1
  mock.next_aug = 1
end

function M.setup()
  extend_package_path()
  if _G.vim then
    ensure_plenary_stub()
    return
  end

  ensure_plenary_stub()

  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  local data_path = tmpdir .. "/poker.nvim-tests"

  local function stdpath(_)
    return data_path
  end

  local function json_encode(_tbl)
    return "{}"
  end

  local function json_decode(_str)
    return {}
  end

  local function mkdir(path, opts)
    if not path or path == "" then
      return 0
    end
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
      os.execute(string.format('mkdir "%s"', path))
    else
      if opts == "p" then
        os.execute(string.format('mkdir -p "%s"', path))
      else
        os.execute(string.format('mkdir "%s"', path))
      end
    end
    return 1
  end

  _G.vim = {
    _mock = {},
    fn = {
      stdpath = stdpath,
      json_encode = json_encode,
      mkdir = mkdir,
      split = split,
      strdisplaywidth = strdisplaywidth,
    },
    json = {
      decode = json_decode,
    },
    uv = {
      hrtime = function()
        return math.floor(os.clock() * 1e9)
      end
    },
    trim = trim,
    tbl_isempty = function(tbl)
      if tbl == nil then
        return true
      end
      return next(tbl) == nil
    end,
    tbl_contains = function(list, value)
      if not list then
        return false
      end
      for _, item in ipairs(list) do
        if item == value then
          return true
        end
      end
      return false
    end,
    list_extend = function(destination, source)
      for _, item in ipairs(source or {}) do
        destination[#destination + 1] = item
      end
      return destination
    end,
    deepcopy = deepcopy,
    log = {
      levels = {
        INFO = 1,
        WARN = 2,
        ERROR = 3,
      },
    },
    o = {
      columns = 80,
      lines = 30,
    },
    api = {},
    ui = {},
  }

  reset_mock_state(vim._mock)
  vim._mock.reset = function()
    reset_mock_state(vim._mock)
  end
  vim._mock.run_deferred = function()
    local queued = vim._mock.deferred
    vim._mock.deferred = {}
    for _, entry in ipairs(queued or {}) do
      if entry.callback then
        entry.callback()
      end
    end
  end

  vim.defer_fn = function(callback, timeout)
    vim._mock.deferred[#vim._mock.deferred + 1] = { callback = callback, timeout = timeout }
  end

  vim.api.nvim_create_namespace = function(name)
    local id = vim._mock.next_ns
    vim._mock.namespaces[id] = name
    vim._mock.next_ns = vim._mock.next_ns + 1
    return id
  end

  vim.api.nvim_set_hl = function(_, group, opts)
    vim._mock.highlight_defs[group] = opts
  end

  vim.api.nvim_buf_is_valid = function(buf)
    return vim._mock.buffers[buf] ~= nil
  end

  vim.api.nvim_create_buf = function(_listed, _scratch)
    local id = vim._mock.next_buf
    vim._mock.next_buf = vim._mock.next_buf + 1
    vim._mock.buffers[id] = { lines = {}, options = {} }
    return id
  end

  vim.api.nvim_buf_set_option = function(buf, key, value)
    if vim._mock.buffers[buf] then
      vim._mock.buffers[buf].options[key] = value
    end
  end

  vim.api.nvim_win_is_valid = function(win)
    return vim._mock.windows[win] ~= nil and vim._mock.windows[win].valid ~= false
  end

  vim.api.nvim_win_get_width = function(win)
    if vim._mock.windows[win] and vim._mock.windows[win].width then
      return vim._mock.windows[win].width
    end
    return vim.o.columns
  end

  vim.api.nvim_buf_set_lines = function(buf, _start, _end_, _strict, lines)
    if not vim._mock.buffers[buf] then
      return
    end
    local copy = {}
    for i, line in ipairs(lines) do
      copy[i] = line
    end
    vim._mock.buffers[buf].lines = copy
  end

  vim.api.nvim_buf_clear_namespace = function(buf, ns, _start, _end_)
    local filtered = {}
    for _, entry in ipairs(vim._mock.highlights) do
      local same_ns = ns == 0 or entry.ns == ns
      if not (entry.buf == buf and same_ns) then
        filtered[#filtered + 1] = entry
      end
    end
    vim._mock.highlights = filtered
  end

  vim.api.nvim_buf_add_highlight = function(buf, ns, group, line, col_start, col_end)
    local entry = {
      buf = buf,
      ns = ns,
      group = group,
      line = line,
      col_start = col_start,
      col_end = col_end,
    }
    vim._mock.highlights[#vim._mock.highlights + 1] = entry
    return #vim._mock.highlights
  end

  vim.api.nvim_buf_delete = function(buf, _opts)
    vim._mock.buffers[buf] = nil
  end

  vim.api.nvim_win_close = function(win, _force)
    if vim._mock.windows[win] then
      vim._mock.windows[win].valid = false
    end
  end

  vim.api.nvim_buf_set_keymap = function(buf, mode, lhs, rhs, opts)
    vim._mock.keymaps[#vim._mock.keymaps + 1] = {
      buf = buf,
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    }
  end

  vim.api.nvim_buf_del_keymap = function(buf, mode, lhs)
    local filtered = {}
    for _, mapping in ipairs(vim._mock.keymaps) do
      if not (mapping.buf == buf and mapping.mode == mode and mapping.lhs == lhs) then
        filtered[#filtered + 1] = mapping
      end
    end
    vim._mock.keymaps = filtered
  end

  vim.api.nvim_create_user_command = function(name, callback, opts)
    vim._mock.commands[name] = { callback = callback, opts = opts }
  end

  vim.api.nvim_win_get_config = function(win)
    local entry = vim._mock.windows[win] or {}
    return {
      relative = "editor",
      width = entry.width or vim.o.columns,
      height = entry.height or vim.o.lines,
      row = entry.row or 0,
      col = entry.col or 0,
    }
  end

  vim.api.nvim_win_set_config = function(win, config)
    if not vim._mock.windows[win] then
      return
    end
    local entry = vim._mock.windows[win]
    entry.width = config.width or entry.width
    entry.height = config.height or entry.height
    entry.row = config.row or entry.row
    entry.col = config.col or entry.col
    entry.config = config
  end

  vim.api.nvim_win_set_cursor = function(win, pos)
    local entry = vim._mock.windows[win]
    if not entry or entry.valid == false then
      return
    end
    if type(pos) ~= "table" then
      return
    end
    entry.cursor = { pos[1], pos[2] or 0 }
  end

  vim.api.nvim_win_get_cursor = function(win)
    local entry = vim._mock.windows[win]
    if entry and entry.cursor then
      return { entry.cursor[1], entry.cursor[2] }
    end
    return { 1, 0 }
  end

  vim.api.nvim_create_augroup = function(name, _opts)
    local id = vim._mock.next_aug
    vim._mock.next_aug = vim._mock.next_aug + 1
    vim._mock.augroups[id] = { name = name }
    return id
  end

  vim.api.nvim_create_autocmd = function(events, opts)
    local id = vim._mock.next_aucmd
    vim._mock.next_aucmd = vim._mock.next_aucmd + 1
    if type(events) ~= "table" then
      events = { events }
    end
    vim._mock.autocmds[#vim._mock.autocmds + 1] = {
      id = id,
      events = events,
      opts = opts or {},
    }
    return id
  end

  vim.api.nvim_del_augroup_by_id = function(id)
    vim._mock.augroups[id] = nil
    local remaining = {}
    for _, cmd in ipairs(vim._mock.autocmds or {}) do
      if cmd.opts and cmd.opts.group ~= id then
        remaining[#remaining + 1] = cmd
      end
    end
    vim._mock.autocmds = remaining
  end

  vim._mock.trigger_autocmd = function(event)
    for _, cmd in ipairs(vim._mock.autocmds or {}) do
      local matches = false
      for _, evt in ipairs(cmd.events or {}) do
        if evt == event then
          matches = true
          break
        end
      end
      if matches and cmd.opts and cmd.opts.callback then
        cmd.opts.callback()
      end
    end
  end

  vim.notify = function(msg, level, opts)
    vim._mock.notifications[#vim._mock.notifications + 1] = { msg = msg, level = level, opts = opts }
  end

  vim.ui.input = function(opts, on_done)
    vim._mock.inputs[#vim._mock.inputs + 1] = opts
    if on_done then
      on_done(nil)
    end
  end
end

return M
