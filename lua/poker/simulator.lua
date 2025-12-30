local acpc = require("poker.export.acpc")
local match = require("poker.match")

local simulator = {}

local function play_one_hand()
  match.start_hand()
  local guard = 0
  while match.current_state ~= match.STATE.HAND_OVER do
    match.progress()
    guard = guard + 1
    if guard > 500 then
      error("Simulation guard exceeded while playing a hand")
    end
  end
end

local function repo_data_dir()
  if match.data_dir then
    return match.data_dir
  end
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  local dir = src:match("(.*/)") or "./"
  local root = dir:gsub("/lua/poker/.*", "")
  return root .. "/data"
end

local function default_log_path()
  local base = repo_data_dir()
  return string.format("%s/sim/acpc_sim_%d.log", base, os.time())
end

---Run a headless simulation of multiple AI-only hands and write an ACPC log.
--- @param opts table { hands: number, players: number, acpc_path: string }
function simulator.run(opts)
  opts = opts or {}
  local hands = opts.hands or 100
  local players = math.max(opts.players or 6, 2)
  local acpc_path = opts.acpc_path or default_log_path()
  local starting_stack = opts.starting_stack
  local small_blind = opts.small_blind
  local big_blind = opts.big_blind
  local seed = opts.seed
  local deck_rng = opts.deck_rng
  local ai_rng = opts.ai_rng

  local original_on_hand_complete = match.on_hand_complete
  local original_config = {
    ai_opponents = match.config.ai_opponents,
    ai_think_ms = match.config.ai_think_ms,
    small_blind = match.config.small_blind,
    big_blind = match.config.big_blind,
    starting_stack = match.config.starting_stack,
    enable_exports = match.config.enable_exports,
    persist_scores = match.config.persist_scores,
  }
  local original_rng = match.get_rng_state()
  local rng_applied = false
  local gamedef_written = false
  local hand_counter = 0
  local function restore_state()
    match.set_on_hand_complete(original_on_hand_complete)
    match.config.ai_opponents = original_config.ai_opponents
    match.config.ai_think_ms = original_config.ai_think_ms
    match.config.small_blind = original_config.small_blind
    match.config.big_blind = original_config.big_blind
    match.config.starting_stack = original_config.starting_stack
    match.config.enable_exports = original_config.enable_exports
    match.config.persist_scores = original_config.persist_scores
    if rng_applied then
      match.restore_rng(original_rng)
    end
  end

  local function setup_ai_table()
    match.start_session()
    if hand_counter > 0 then
      match.hand_id = hand_counter
    end
    for idx, p in ipairs(match.players) do
      p.is_human = false
      if not p.name or p.name == "You" then
        p.name = string.format("AI%d", p.id or idx)
      end
    end
  end

  local function run_simulation()
    match.config.ai_opponents = players - 1
    match.config.ai_think_ms = 0
    if starting_stack ~= nil then
      match.config.starting_stack = starting_stack
    end
    if small_blind ~= nil then
      match.config.small_blind = small_blind
    end
    if big_blind ~= nil then
      match.config.big_blind = big_blind
    end
    match.config.enable_exports = false
    match.config.persist_scores = false

    if seed ~= nil then
      match.set_seed(seed)
      rng_applied = true
    elseif deck_rng or ai_rng then
      match.set_rng(deck_rng, ai_rng)
      rng_applied = true
    end

    setup_ai_table()

    match.set_on_hand_complete(function(hand_state)
      if not gamedef_written then
        local gd = acpc.serialize_gamedef({
          small_blind = match.config.small_blind,
          big_blind = match.config.big_blind,
          starting_stack = match.config.starting_stack,
          players = #hand_state.players,
        })
        acpc.write_log(acpc_path, gd)
        gamedef_written = true
      end
      acpc.write_log(acpc_path, acpc.serialize_state(hand_state.id, hand_state))
    end)

    for _ = 1, hands do
      if #match.players <= 1 then
        setup_ai_table()
      end
      play_one_hand()
      hand_counter = match.hand_id or hand_counter
    end

    return acpc_path
  end

  local ok, result = xpcall(run_simulation, function(err)
    return debug.traceback(err, 2)
  end)
  restore_state()
  if not ok then
    error(result)
  end
  return result
end

return simulator
