local M = {}

local function sanitize_non_negative_integer(value)
  local num = tonumber(value)
  if not num then
    return nil
  end
  num = math.floor(num)
  if num < 0 then
    return nil
  end
  return num
end

local function resolve_decoder()
  if vim and vim.json and type(vim.json.decode) == "function" then
    return vim.json.decode
  end
  if vim and vim.fn and type(vim.fn.json_decode) == "function" then
    return vim.fn.json_decode
  end
  return nil
end

function M.setup(ctx)
  local match = ctx.match
  local stats = ctx.stats
  local fs = ctx.fs
  local default_scores_path = ctx.default_scores_path
  local schema_version = ctx.schema_version

  local function get_scores_path()
    if match.config.scores_path == nil then
      return default_scores_path
    end
    return match.config.scores_path
  end

  local function ensure_stats_tracker()
    if match.stats.tracker == nil then
      match.stats.tracker = stats.new_store()
    else
      match.stats.tracker = stats.ensure_store(match.stats.tracker)
    end
  end

  local function write_scores()
    if match.config.persist_scores == false then
      return
    end
    local payload = vim.fn.json_encode({
      schema_version = schema_version,
      stats = match.stats,
    })
    fs.atomic_write(get_scores_path(), payload)
  end

  local function read_scores()
    if match.config.persist_scores == false then
      ensure_stats_tracker()
      return
    end
    local contents = fs.read_file(get_scores_path())
    if not contents then
      ensure_stats_tracker()
      return
    end
    local decoder = resolve_decoder()
    local ok, decoded = pcall(function()
      if decoder == nil then
        error("no json decoder available")
      end
      return decoder(contents)
    end)
    if ok and decoded and type(decoded) == "table" then
      local payload = decoded
      if decoded.schema_version ~= nil and type(decoded.stats) == "table" then
        payload = decoded.stats
      end

      local function assign_count(key)
        local value = sanitize_non_negative_integer(payload[key])
        if value ~= nil then
          match.stats[key] = value
        end
      end

      assign_count("hands_played")
      assign_count("player_wins")
      assign_count("player_losses")
      assign_count("player_ties")

      if payload.tracker ~= nil then
        if type(payload.tracker) == "table" then
          match.stats.tracker = stats.ensure_store(payload.tracker)
        else
          match.stats.tracker = stats.new_store()
        end
      end
    end
    ensure_stats_tracker()
  end

  return {
    get_scores_path = get_scores_path,
    ensure_stats_tracker = ensure_stats_tracker,
    write_scores = write_scores,
    read_scores = read_scores,
  }
end

return M
