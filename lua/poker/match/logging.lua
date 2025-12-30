local M = {}

local function parent_dir(path_str)
  if not path_str then
    return ""
  end
  local stripped = path_str:gsub("[/\\][^/\\]+[/\\]?$", "")
  if stripped == path_str then
    return ""
  end
  return stripped
end

local function plugin_data_dir(match)
  if match.data_dir then
    return match.data_dir
  end
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  local dir = src:match("(.*/)") or "./"
  local root = parent_dir(parent_dir(dir))
  local data_dir = root .. "/data"
  match.data_dir = data_dir
  return data_dir
end

local function canonical_street(name, street_order)
  if not name then
    return "preflop"
  end
  if type(name) == "number" then
    name = street_order[name] or "pre-flop"
  end
  name = name:lower()
  name = name:gsub("%W", "")
  if name == "preflop" then
    return "preflop"
  end
  return name
end

function M.setup(ctx)
  local match = ctx.match
  local cards = ctx.cards
  local opponent_model = ctx.opponent_model
  local stats = ctx.stats
  local fs = ctx.fs
  local ensure_stats_tracker = ctx.ensure_stats_tracker
  local write_scores = ctx.write_scores
  local find_seat = ctx.find_seat

  local function current_street_name()
    return canonical_street(match.street_order[match.current_street_index] or "pre-flop", match.street_order)
  end

  local function init_hand_log()
    match.hand_id = (match.hand_id or 0) + 1
    local snapshot = {}
    for idx, player in ipairs(match.players) do
      snapshot[#snapshot + 1] = {
        id = player.id,
        name = player.name,
        seat = idx,
        stack_start = player.stack,
        is_human = player.is_human,
        hole_cards = cards.clone_many(player.hole_cards),
      }
    end
    match.current_hand_log = {
      id = match.hand_id,
      config = {
        small_blind = match.config.small_blind,
        big_blind = match.config.big_blind,
        starting_stack = match.config.starting_stack,
        table_name = match.config.table_name,
      },
      button_index = match.button_index,
      actions = {},
      players = snapshot,
      board = {},
      pot = 0,
    }
  end

  local function record_action(player, action, amount, total, extra)
    if not match.current_hand_log then
      return
    end
    local seat = find_seat(player)
    local street = current_street_name()
    match.current_hand_log.actions[#match.current_hand_log.actions + 1] = {
      street = street,
      player_id = player and player.id or nil,
      player_name = player and player.name or nil,
      seat = seat,
      action = action,
      amount = amount or 0,
      total = total,
      info = extra,
    }
    if player and action ~= "blind" then
      opponent_model.record_action(player.id, action, amount or 0, street)
    end
  end

  local function finalize_hand_log(context)
    local log = match.current_hand_log
    if not log then
      return
    end
    log.board = cards.clone_many(match.board)
    log.pot = context and context.pot or log.pot or 0
    log.showdown = context and context.showdown or log.showdown
    log.players_final = {}
    for idx, player in ipairs(match.players) do
      log.players_final[#log.players_final + 1] = {
        id = player.id,
        name = player.name,
        seat = idx,
        stack_end = player.stack,
        hole_cards = cards.clone_many(player.hole_cards),
        folded = player.folded,
        is_human = player.is_human,
      }
    end
    if match.config.enable_exports then
      local ok_acpc, acpc = pcall(require, "poker.export.acpc")
      local ok_ps, ps = pcall(require, "poker.export.pokerstars")
      if ok_acpc and ok_ps then
        local data_dir = plugin_data_dir(match)
        fs.ensure_dir(data_dir)
        local acpc_path = match.config.export_acpc_path or (data_dir .. "/acpc.log")
        local ps_dir = match.config.export_pokerstars_dir or (data_dir .. "/pokerstars")
        fs.ensure_dir(ps_dir)
        acpc.write_log(acpc_path, acpc.serialize_state(log.id, log))
        local ps_path = string.format("%s/hand_%s.txt", ps_dir, tostring(log.id or ""))
        ps.write_hand(ps_path, ps.serialize_hand(log))
      end
    end
    ensure_stats_tracker()
    stats.record_hand(match.stats.tracker, log)
    write_scores()
    if type(match.on_hand_complete) == "function" then
      pcall(match.on_hand_complete, log)
    end
    match.last_hand_log = log
    match.current_hand_log = nil
  end

  return {
    init_hand_log = init_hand_log,
    record_action = record_action,
    finalize_hand_log = finalize_hand_log,
  }
end

return M
