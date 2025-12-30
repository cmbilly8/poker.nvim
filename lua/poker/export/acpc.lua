local cards = require("poker.cards")
local fs = require("poker.fs")

local acpc = {}

local SUIT_MAP = {
  [0] = "c",
  [1] = "d",
  [2] = "h",
  [3] = "s",
}

local RANK_MAP = {
  [10] = "T",
  [11] = "J",
  [12] = "Q",
  [13] = "K",
  [14] = "A",
}

local function fmt_card(card)
  if not card then
    return "xx"
  end
  local rank = RANK_MAP[card.rank] or tostring(card.rank or "?")
  local suit = SUIT_MAP[card.suit] or "x"
  return rank .. suit
end

local function fmt_cards(list)
  local parts = {}
  for _, card in ipairs(list or {}) do
    parts[#parts + 1] = fmt_card(card)
  end
  return table.concat(parts, "")
end

---Serialize the current game definition for ACPC.
---Fields: small_blind, big_blind, starting_stack, players (numPlayers), first_player (array)
function acpc.serialize_gamedef(config)
  config = config or {}
  local num_players = config.players or config.numPlayers or 2
  local first = config.first_player or { 1, 1, 1, 1 }
  local lines = {
    "GAMEDEF",
    (config.limit or "nolimit"),
    string.format("numPlayers %d", num_players),
    "numRounds 4",
    string.format("blind ante 0 %d %d", config.small_blind or 0, config.big_blind or 0),
    string.format("stack %d", config.starting_stack or 0),
    "raiseSize 0 0 0 0",
    string.format("firstPlayer %s", table.concat(first, " ")),
  }
  return table.concat(lines, "\n")
end

local function canonical_street(name)
  if not name or name == "" then
    return "preflop"
  end
  return name:gsub("%W", ""):lower()
end

local function encode_actions(actions, street)
  local buffer = {}
  local target = canonical_street(street)
  for _, action in ipairs(actions or {}) do
    if canonical_street(action.street) == target then
      local code = "c"
      if action.action == "fold" then
        code = "f"
      elseif action.action == "raise" or action.action == "bet" or action.action == "blind" then
        code = string.format("r%d", action.total or action.amount or 0)
      else
        code = "c"
      end
      buffer[#buffer + 1] = code
    end
  end
  return table.concat(buffer, "")
end

---Serialize a match state line (STATE:<id>:history:hole:board)
function acpc.serialize_state(hand_id, state)
  state = state or {}
  local players = state.players or {}
  local hero_id = nil
  for _, p in ipairs(players) do
    if p.is_human then
      hero_id = p.id
      break
    end
  end
  if not hero_id and players[1] then
    hero_id = players[1].id
  end

  local hole_parts = {}
  for _, player in ipairs(players) do
    if player.id == hero_id then
      hole_parts[#hole_parts + 1] = fmt_card(player.hole_cards and player.hole_cards[1])
        .. fmt_card(player.hole_cards and player.hole_cards[2])
    else
      hole_parts[#hole_parts + 1] = "xx"
    end
  end

  local history = table.concat({
    encode_actions(state.actions or {}, "preflop"),
    encode_actions(state.actions or {}, "flop"),
    encode_actions(state.actions or {}, "turn"),
    encode_actions(state.actions or {}, "river"),
  }, "/")

  local board = fmt_cards(state.board or {})

  return string.format("STATE:%s:%s:%s:%s", tostring(hand_id or ""), history, table.concat(hole_parts, "|"), board)
end

local function existing_file_status(target_path)
  local f = fs.open(target_path, "r")
  if not f then
    return false, false
  end

  local size = f:seek("end")
  if not size or size == 0 then
    f:close()
    return true, false
  end

  f:seek("end", -1)
  local last = f:read(1)
  f:close()

  return true, last ~= "\n"
end

function acpc.write_log(target_path, line)
  if not target_path or not line then
    return
  end
  local dir = target_path:match("(.+)/[^/]+$")
  fs.ensure_dir(dir)

  local _, needs_newline = existing_file_status(target_path)

  local f = fs.open(target_path, "a")
  if not f then
    return
  end

  if needs_newline then
    f:write("\n")
  end

  f:write(line)
  if not line:match("\n$") then
    f:write("\n")
  end

  f:close()
end

return acpc
