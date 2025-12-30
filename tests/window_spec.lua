local helper = require("tests.helpers.mock_vim")
helper.setup()

package.preload["plenary.popup"] = function()
  local next_win = 1
  local popup = {
    _borders = {},
  }
  local function normalize(value)
    if value == nil then
      return 0
    end
    if value <= 0 then
      return 0
    end
    return value - 1
  end
  local function ensure_border(win_id, win)
    if not popup._borders[win_id] then
      local border_id = next_win
      next_win = next_win + 1
      popup._borders[win_id] = {
        win_id = border_id,
        _border_win_options = {
          border_thickness = { top = 1, right = 1, bot = 1, left = 1 },
        },
      }
      if win then
        vim._mock.windows[border_id] = {
          width = (win.width or 0) + 2,
          height = (win.height or 0) + 2,
          row = math.max((win.row or 0) - 1, 0),
          col = math.max((win.col or 0) - 1, 0),
          valid = true,
          is_border = true,
        }
      end
    end
    return popup._borders[win_id]
  end

  function popup.create(_, opts)
    local id = next_win
    next_win = next_win + 1
    local width = opts and (opts.width or opts.minwidth) or vim.o.columns
    local height = opts and (opts.height or opts.minheight) or vim.o.lines
    vim._mock.windows[id] = {
      width = width,
      height = height,
      row = normalize(opts and opts.line),
      col = normalize(opts and opts.col),
      valid = true,
    }
    ensure_border(id, vim._mock.windows[id])
    return id, popup._borders[id].win_id
  end

  function popup.move(win_id, opts)
    local win = vim._mock.windows[win_id]
    if not win or win.valid == false then
      return
    end
    ensure_border(win_id)
    if opts then
      if opts.width then
        win.width = opts.width
      end
      if opts.height then
        win.height = opts.height
      end
      if opts.line then
        win.row = normalize(opts.line)
      end
      if opts.col then
        win.col = normalize(opts.col)
      end
    end
  end

  return popup
end

local window = require("poker.window")
local match = require("poker.match")

local BOARD_CARD_HEIGHT = 5
local EVENT_FEED_WIDTH = 30
local EVENT_SEP_WIDTH = 2
local find_pot_line_index

local function current_window()
  for id, win in pairs(vim._mock.windows) do
    if win.valid ~= false and not win.is_border then
      return id, win
    end
  end
  return nil, nil
end

local function border_window_for(win_id)
  local popup_stub = require("plenary.popup")
  if not popup_stub._borders then
    return nil, nil, nil
  end
  local border = popup_stub._borders[win_id]
  if not border then
    return nil, nil, nil
  end
  return border.win_id, vim._mock.windows[border.win_id], border._border_win_options.border_thickness
end

local function first_buffer_lines()
  for _, buf in pairs(vim._mock.buffers) do
    return buf.lines or {}
  end
  return {}
end

local function current_content_width()
  local _, win = current_window()
  if win and win.width then
    return win.width
  end
  return math.max(vim.o.columns - 2, 1)
end

local function current_event_width()
  local required_left = math.max((5 + 2) * 5 + (2 * 4), 30)
  local max_event = math.max(current_content_width() - EVENT_SEP_WIDTH - required_left, 0)
  return math.min(EVENT_FEED_WIDTH, max_event)
end

local function current_content_height()
  local _, win = current_window()
  if win and win.height then
    return win.height
  end
  return math.max(vim.o.lines - 2, 1)
end

local function current_left_width()
  return math.max(current_content_width() - current_event_width() - EVENT_SEP_WIDTH, 0)
end

local function current_window_margins()
  local _, win = current_window()
  if not win then
    return nil
  end
  local total_width = (win.width or 0) + 2
  local total_height = (win.height or 0) + 2
  local left = win.col or 0
  local top = win.row or 0
  local right = math.max(vim.o.columns - total_width - left, 0)
  local bottom = math.max(vim.o.lines - total_height - top, 0)
  return left, right, top, bottom
end

local function byte_index_for_display_width(text, target_width)
  local acc = 0
  local bytes = 0
  for _, ch in ipairs(vim.fn.split(text or "", [[\zs]])) do
    local w = vim.fn.strdisplaywidth(ch)
    if acc + w > target_width then
      break
    end
    acc = acc + w
    bytes = bytes + #ch
  end
  return bytes
end

local function left_chunk(line)
  local left_width = current_left_width()
  if left_width < 1 then
    return ""
  end
  local bytes = byte_index_for_display_width(line or "", left_width)
  return (line or ""):sub(1, bytes)
end

local function right_chunk(line)
  local left_width = current_left_width()
  local start_bytes = byte_index_for_display_width(line or "", left_width + EVENT_SEP_WIDTH) + 1
  if start_bytes > #(line or "") then
    return ""
  end
  return (line or ""):sub(start_bytes)
end

local function find_player_card_range(lines)
  local stats_idx = nil
  for i, line in ipairs(lines) do
    if vim.trim(left_chunk(line)):find("Stack:", 1, true) then
      stats_idx = i
      break
    end
  end
  if not stats_idx then
    return nil, nil
  end
  local bottom_idx = stats_idx - 1
  local top_idx = nil
  for i = bottom_idx, 1, -1 do
    local chunk = left_chunk(lines[i])
    if chunk:find("┌", 1, true) or chunk:find("╭", 1, true) then
      top_idx = i
      break
    end
  end
  return top_idx, bottom_idx
end

local function find_board_top_line(lines)
  local pot_idx = find_pot_line_index(lines)
  if not pot_idx then
    return nil
  end
  local top_idx = pot_idx - BOARD_CARD_HEIGHT
  if top_idx < 1 then
    return nil
  end
  return left_chunk(lines[top_idx] or "")
end

local function find_board_start_index(lines)
  local pot_idx = find_pot_line_index(lines)
  if not pot_idx then
    return nil
  end
  local start_idx = pot_idx - BOARD_CARD_HEIGHT
  if start_idx < 1 then
    return nil
  end
  return start_idx
end

local function find_last_opponent_line_before_board(lines)
  local board_idx = find_board_start_index(lines)
  if not board_idx then
    return nil
  end
  local last = nil
  for i = 1, board_idx - 1 do
    local chunk = left_chunk(lines[i])
    if chunk:find("┘", 1, true) or chunk:find("╯", 1, true) or chunk:find("╰", 1, true) then
      last = i
    end
  end
  return last, board_idx
end

function find_pot_line_index(lines)
  for i, line in ipairs(lines) do
    if left_chunk(line):find("Pot:", 1, true) then
      return i
    end
  end
  return nil
end

local function find_event_top_index(lines)
  for i, line in ipairs(lines) do
    local chunk = right_chunk(line)
    if chunk:find("╭", 1, true) and chunk:find("╮", 1, true) then
      return i
    end
  end
  return nil
end

local function find_event_bottom_index(lines)
  for i = #lines, 1, -1 do
    local chunk = right_chunk(lines[i])
    if chunk:find("╰", 1, true) and chunk:find("╯", 1, true) then
      return i
    end
  end
  return nil
end

local function find_player_bottom_index(lines)
  for i = #lines, 1, -1 do
    local chunk = left_chunk(lines[i])
    if chunk:find("╰", 1, true) and chunk:find("╯", 1, true) then
      return i
    end
  end
  return nil
end

local function whitespace_balance(line)
  local chunk = left_chunk(line)
  local leading = #(chunk:match("^(%s*)") or "")
  local trailing = #(chunk:match("(%s*)$") or "")
  local trimmed = vim.trim(chunk)
  return leading, trailing, trimmed
end

local function has_highlight_in_range(group, start_line, end_line)
  for _, hl in ipairs(vim._mock.highlights) do
    if hl.group == group then
      local line = (hl.line or 0) + 1
      if (not start_line or line >= start_line) and (not end_line or line <= end_line) then
        return true
      end
    end
  end
  return false
end

local function setup_match(players, state, opts)
  opts = opts or {}
  match.get_players = function()
    return players
  end
  match.get_board = function()
    return opts.board or {}
  end
  match.current_state = state
  match.current_player_index = 1
  match.pot = opts.pot or 50
  match.current_bet = opts.current_bet or 10
end

local function has_highlight(group)
  for _, hl in ipairs(vim._mock.highlights) do
    if hl.group == group then
      return true
    end
  end
  return false
end

describe("window opponent borders", function()
  local original_get_players
  local original_get_board
  local original_state
  local original_current
  local original_pot
  local original_bet
  local original_events
  local original_start_session
  local original_start_hand
  local original_progress
  local original_waiting
  local original_panel_width

  before_each(function()
    vim.o.columns = 80
    vim.o.lines = 30
    match.config.ai_think_ms = 0
    match.waiting_on_ai = false
    original_panel_width = window.player_panel_width
    original_get_players = match.get_players
    original_get_board = match.get_board
    original_state = match.current_state
    original_current = match.current_player_index
    original_pot = match.pot
    original_bet = match.current_bet
    original_events = match.last_events
    original_start_session = match.start_session
    original_start_hand = match.start_hand
    original_progress = match.progress
    original_waiting = match.waiting_on_ai
    vim._mock.reset()
    window.destroy()
  end)

  after_each(function()
    match.get_players = original_get_players
    match.get_board = original_get_board
    match.current_state = original_state
    match.current_player_index = original_current
    match.pot = original_pot
    match.current_bet = original_bet
    match.last_events = original_events
    match.start_session = original_start_session
    match.start_hand = original_start_hand
    match.progress = original_progress
    match.waiting_on_ai = original_waiting
    window.player_panel_width = original_panel_width
    window.destroy()
  end)

  it("highlights folded opponent cards with a red border", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 100,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "A", suit = 0, rank = 14, revealed = true },
          { symbol = "K", suit = 3, rank = 13, revealed = true },
        },
      },
      {
        name = "Folder",
        stack = 80,
        bet_in_round = 0,
        folded = true,
        hole_cards = {
          { symbol = "2", suit = 1, rank = 2, revealed = true },
          { symbol = "7", suit = 2, rank = 7, revealed = true },
        },
      },
    }
    setup_match(players, match.STATE.HAND_OVER)
    window.open_table()
    window.render()
    assert.is_true(has_highlight("PokerPlayerFoldBorder"))
  end)

  it("highlights winning opponent cards with a green border", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 120,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "J", suit = 2, rank = 11, revealed = true },
          { symbol = "9", suit = 0, rank = 9, revealed = true },
        },
      },
      {
        name = "Winner",
        stack = 180,
        bet_in_round = 0,
        last_action = "won 60",
        hole_cards = {
          { symbol = "Q", suit = 3, rank = 12, revealed = true },
          { symbol = "Q", suit = 1, rank = 12, revealed = true },
        },
      },
    }
    setup_match(players, match.STATE.HAND_OVER)
    window.open_table()
    window.render()
    assert.is_true(has_highlight("PokerPlayerWinBorder"))
  end)

  it("shows recent events in the event feed", function()
    match.last_events = { "AI folded", "You checked" }
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local lines = table.concat(first_buffer_lines(), "\n")
    assert.is_true(lines:find("Recent Events", 1, true) ~= nil)
    assert.is_true(lines:find("AI folded", 1, true) ~= nil)
    assert.is_true(lines:find("You checked", 1, true) ~= nil)
  end)

  it("adds the stats hint at the bottom of the event feed", function()
    match.last_events = { "Alpha" }
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()

    local lines = first_buffer_lines()
    local event_top = find_event_top_index(lines)
    local event_bottom = find_event_bottom_index(lines)
    assert.is_not_nil(event_top)
    assert.is_not_nil(event_bottom)

    local prompt_index = nil
    for i, line in ipairs(lines) do
      local chunk = right_chunk(line)
      if chunk:find("Press ; for stats", 1, true) then
        prompt_index = i
        break
      end
    end

    assert.is_not_nil(prompt_index)
    assert.are.equal(event_bottom - 1, prompt_index)
    local divider = right_chunk(lines[prompt_index - 1] or "")
    assert.is_true(divider:find("├", 1, true) ~= nil)
    assert.is_true(divider:find("┤", 1, true) ~= nil)
  end)

  it("wraps the recent events with a full border", function()
    match.last_events = { "Alpha", "Beta" }
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local top_border, bottom_border, right_border = false, false, false
    for _, line in ipairs(lines) do
      local chunk = right_chunk(line)
      if chunk:find("╭", 1, true) and chunk:find("╮", 1, true) then
        top_border = true
        assert.are.equal(current_event_width(), vim.fn.strdisplaywidth(vim.trim(chunk)))
      end
      if chunk:find("╰", 1, true) and chunk:find("╯", 1, true) then
        bottom_border = true
      end
      if chunk:find("│", 1, true) then
        right_border = true
      end
      assert.is_nil(chunk:find("┆", 1, true))
    end
    assert.is_true(top_border)
    assert.is_true(bottom_border)
    assert.is_true(right_border)
  end)

  it("positions the event feed below the opponent bets", function()
    match.last_events = { "Alpha", "Beta" }
    local players = {
      { name = "Hero", is_human = true, stack = 200, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 150, bet_in_round = 40, last_action = "raise to 40", hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local last_opponent_line = select(1, find_last_opponent_line_before_board(lines))
    local event_top = find_event_top_index(lines)
    local event_bottom = find_event_bottom_index(lines)
    local player_bottom = find_player_bottom_index(lines)
    assert.is_not_nil(last_opponent_line)
    assert.is_not_nil(event_top)
    assert.is_not_nil(event_bottom)
    assert.is_not_nil(player_bottom)
    assert.is_true(event_top >= last_opponent_line + 2)
    local amount_idx = nil
    for i = last_opponent_line + 1, event_top - 1 do
      if vim.trim(left_chunk(lines[i] or "")):match("^%d+$") then
        amount_idx = i
        break
      end
    end
    assert.is_not_nil(amount_idx)
    local spacer = left_chunk(lines[event_top - 1] or "")
    assert.are.equal("", vim.trim(spacer))
    assert.are.equal(event_bottom, player_bottom)
  end)

  it("hides folded opponent cards until the hand ends", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 100,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "A", suit = 0, rank = 14, revealed = true },
          { symbol = "K", suit = 1, rank = 13, revealed = true },
        },
      },
      {
        name = "Folder",
        stack = 90,
        bet_in_round = 0,
        folded = true,
        hole_cards = {
          { symbol = "2", suit = 1, rank = 2, revealed = true },
          { symbol = "7", suit = 2, rank = 7, revealed = true },
        },
      },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local combined = table.concat(first_buffer_lines(), "\n")
    assert.is_true(combined:find("%[%?%?%]%s+%[%?%?%]") ~= nil)
    assert.is_nil(combined:find("[2", 1, true))
    assert.is_nil(combined:find("[7", 1, true))

    setup_match(players, match.STATE.HAND_OVER)
    window.render()
    local showdown = table.concat(first_buffer_lines(), "\n")
    assert.is_true(showdown:find("[2", 1, true) ~= nil)
    assert.is_true(showdown:find("[7", 1, true) ~= nil)
  end)

  it("highlights the player's border during their turn", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 150,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "A", suit = 0, rank = 14, revealed = true },
          { symbol = "K", suit = 1, rank = 13, revealed = true },
        },
      },
      {
        name = "Villain",
        stack = 90,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "9", suit = 2, rank = 9, revealed = true },
          { symbol = "8", suit = 3, rank = 8, revealed = true },
        },
      },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local start_line, end_line = find_player_card_range(first_buffer_lines())
    assert.is_not_nil(start_line)
    assert.is_true(has_highlight_in_range("PokerPlayerActiveBorder", start_line, end_line))
  end)

  it("does not highlight the player's border when it is an opponent's turn", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.AI_TURN)
    match.current_player_index = 2
    window.open_table()
    window.render()
    local start_line, end_line = find_player_card_range(first_buffer_lines())
    assert.is_not_nil(start_line)
    assert.is_false(has_highlight_in_range("PokerPlayerActiveBorder", start_line, end_line))
  end)

  it("highlights the player border in a real hand when it is their turn", function()
    match.start_session()
    match.start_hand()
    local guard = 0
    while match.current_state ~= match.STATE.PLAYER_TURN do
      match.progress()
      guard = guard + 1
      if guard > 50 then
        error("player turn not reached")
      end
    end
    window.open_table()
    window.render()
    local start_line, end_line = find_player_card_range(first_buffer_lines())
    assert.is_not_nil(start_line)
    assert.is_true(has_highlight_in_range("PokerPlayerActiveBorder", start_line, end_line))
  end)

  it("shows a skip prompt while waiting on AI turns", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.AI_TURN)
    match.waiting_on_ai = true
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local found = false
    for _, line in ipairs(lines) do
      if line:find("skip to turn", 1, true) then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)

  it("omits the close action when a hand ends naturally", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.HAND_OVER)
    window.open_table()
    window.render()
    local lines = table.concat(first_buffer_lines(), "\n")
    assert.is_nil(lines:find("close", 1, true))
    assert.is_true(lines:find("next hand", 1, true) ~= nil)
  end)

  it("shows a showdown prompt when waiting to reveal results", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.SHOWDOWN)
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local found = false
    for _, line in ipairs(lines) do
      if line:lower():find("showdown", 1, true) then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)

  it("lets the player panel width be customized independently", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.player_panel_width = 30
    window.open_table()
    window.render()
    local default_lines = first_buffer_lines()
    local top_default_idx = select(1, find_player_card_range(default_lines))
    assert.is_not_nil(top_default_idx)
    local top_default = vim.trim(left_chunk(default_lines[top_default_idx]))

    window.player_panel_width = 20
    window.render()
    local smaller_lines = first_buffer_lines()
    local top_smaller_idx = select(1, find_player_card_range(smaller_lines))
    assert.is_not_nil(top_smaller_idx)
    local top_smaller = vim.trim(left_chunk(smaller_lines[top_smaller_idx]))
    assert.is_true(vim.fn.strdisplaywidth(top_smaller) < vim.fn.strdisplaywidth(top_default))
  end)

  it("centers the player panel under the board", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.player_panel_width = 20
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local top_idx = select(1, find_player_card_range(lines))
    assert.is_not_nil(top_idx)
    local lead, trail, _ = whitespace_balance(lines[top_idx])
    assert.is_true(math.abs(lead - trail) <= 1)
  end)

  it("uses rounded corners for player and opponent boxes", function()
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local player_top = select(1, find_player_card_range(lines))
    assert.is_not_nil(player_top)
    local player_line = left_chunk(lines[player_top])
    assert.is_truthy(player_line:find("╭", 1, true))
    assert.is_truthy(player_line:find("╮", 1, true))

    local has_opponent_round = false
    for _, line in ipairs(lines) do
      local chunk = left_chunk(line)
      if chunk:find("╭", 1, true) and chunk:find("╮", 1, true) and chunk:find("stack:", 1, true) == nil then
        has_opponent_round = true
        break
      end
    end
    assert.is_true(has_opponent_round)
  end)

  it("keeps board card positions fixed as cards are revealed", function()
    local base_board = {}
    local flop_board = {
      { symbol = "A", suit = 0, rank = 14, revealed = true },
      { symbol = "K", suit = 1, rank = 13, revealed = true },
      { symbol = "Q", suit = 2, rank = 12, revealed = true },
    }
    local river_board = {
      { symbol = "A", suit = 0, rank = 14, revealed = true },
      { symbol = "K", suit = 1, rank = 13, revealed = true },
      { symbol = "Q", suit = 2, rank = 12, revealed = true },
      { symbol = "J", suit = 3, rank = 11, revealed = true },
      { symbol = "T", suit = 0, rank = 10, revealed = true },
    }
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN, { board = base_board })
    window.open_table()
    window.render()
    local empty_line = find_board_top_line(first_buffer_lines())
    assert.is_not_nil(empty_line)

    setup_match(players, match.STATE.PLAYER_TURN, { board = flop_board })
    window.render()
    local flop_line = find_board_top_line(first_buffer_lines())
    assert.is_not_nil(flop_line)

    setup_match(players, match.STATE.PLAYER_TURN, { board = river_board })
    window.render()
    local river_line = find_board_top_line(first_buffer_lines())
    assert.is_not_nil(river_line)

    assert.are.equal(vim.fn.strdisplaywidth(flop_line), vim.fn.strdisplaywidth(river_line))
    local function first_non_space(line)
      local idx = left_chunk(line):find("%S")
      if not idx then
        return (left_chunk(line) or ""):len() + 1
      end
      return idx
    end
    assert.are.equal(first_non_space(flop_line), first_non_space(river_line))
  end)

  it("renders the board above the pot without a label", function()
    local board = {
      { symbol = "A", suit = 0, rank = 14, revealed = true },
      { symbol = "K", suit = 1, rank = 13, revealed = true },
      { symbol = "Q", suit = 2, rank = 12, revealed = true },
    }
    local players = {
      { name = "Hero", is_human = true, stack = 100, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN, { board = board, pot = 120, current_bet = 40 })
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local has_label = false
    for _, line in ipairs(lines) do
      if vim.trim(left_chunk(line)) == "Board:" then
        has_label = true
        break
      end
    end
    assert.is_false(has_label)
    local pot_idx = find_pot_line_index(lines)
    assert.is_not_nil(pot_idx)
    local board_top = find_board_top_line(lines)
    assert.is_not_nil(board_top)
    assert.is_truthy(board_top:find("┌", 1, true))
    assert.is_truthy(board_top:find("┐", 1, true))
    assert.is_nil(board_top:find("Pot:", 1, true))
    assert.is_nil(board_top:find("Bets:", 1, true))
    assert.is_true(pot_idx > 1)
  end)

  it("centers the opponent status inside their box", function()
    local players = {
      { name = "Hero", is_human = true, stack = 200, bet_in_round = 0, hole_cards = {} },
      {
        name = "Villain",
        stack = 150,
        bet_in_round = 0,
        last_action = "posts big blind 20",
        hole_cards = {},
      },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local board_start = find_board_start_index(lines)
    assert.is_not_nil(board_start)

    local status_line = nil
    for i = 1, board_start - 1 do
      local line = lines[i] or ""
      if line:find("│%s*BB%s*│") then
        status_line = line
        break
      end
    end
    assert.is_not_nil(status_line)
    local inner = status_line:match("│(.*)│")
    assert.is_not_nil(inner)
    assert.are.equal("BB", vim.trim(inner))
    local leading = #(inner:match("^(%s*)") or "")
    local trailing = #(inner:match("(%s*)$") or "")
    assert.is_true(math.abs(leading - trailing) <= 1)
  end)

  it("shows opponent bet amounts in the gap beneath their cards", function()
    local players = {
      { name = "Hero", is_human = true, stack = 200, bet_in_round = 0, hole_cards = {} },
      {
        name = "Villain",
        stack = 150,
        bet_in_round = 40,
        last_action = "raise to 40",
        hole_cards = {},
      },
    }
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 120, current_bet = 40 })
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local last_opponent_line, board_start = find_last_opponent_line_before_board(lines)
    assert.is_not_nil(board_start)
    assert.is_not_nil(last_opponent_line)
    assert.is_true(board_start > last_opponent_line + 1)

    local gap_has_amount = false
    for i = last_opponent_line + 1, board_start - 1 do
      if left_chunk(lines[i]):find("40", 1, true) then
        gap_has_amount = true
        break
      end
    end
    assert.is_true(gap_has_amount)

    local status_line = nil
    for i = 1, last_opponent_line do
      if left_chunk(lines[i]):find("raise", 1, true) then
        status_line = left_chunk(lines[i])
        break
      end
    end
    assert.is_not_nil(status_line)
    assert.is_nil(status_line:find("40", 1, true))
  end)

  it("shows the player's contribution above their panel", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 90,
        bet_in_round = 0,
        last_action = "call 30",
        hole_cards = {},
      },
      { name = "Villain", stack = 120, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 200, current_bet = 30 })
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    local pot_idx = find_pot_line_index(lines)
    assert.is_not_nil(pot_idx)
    local player_top = select(1, find_player_card_range(lines))
    assert.is_not_nil(player_top)
    assert.is_true(player_top > pot_idx + 1)

    local gap_has_amount = false
    local amount_idx = nil
    for i = pot_idx + 1, player_top - 1 do
      if left_chunk(lines[i]):find("30", 1, true) then
        gap_has_amount = true
        amount_idx = i
        break
      end
    end
    assert.is_true(gap_has_amount)
    assert.is_not_nil(amount_idx)
    assert.is_true(amount_idx >= pot_idx + 2)
    local spacer = left_chunk(lines[pot_idx + 1] or "")
    assert.are.equal("", vim.trim(spacer))
  end)

  it("resizes the popup when the editor is resized", function()
    local players = {
      { name = "Hero", is_human = true, stack = 120, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 100, bet_in_round = 10, last_action = "call 10", hole_cards = {} },
    }
    vim.o.columns = 120
    vim.o.lines = 40
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 80, current_bet = 10 })
    window.open_table()
    window.render()
    local initial_width = current_content_width()
    assert.is_true(initial_width >= 100)

    vim.o.columns = 72
    vim.o.lines = 24
    vim._mock.trigger_autocmd("VimResized")
    local resized_width = current_content_width()
    assert.is_true(resized_width < initial_width)
    assert.is_true(resized_width <= vim.o.columns - 2)

    window.render()
    local lines = first_buffer_lines()
    local event_top = find_event_top_index(lines)
    assert.is_not_nil(event_top)
    local chunk = right_chunk(lines[event_top])
    assert.are.equal(current_event_width(), vim.fn.strdisplaywidth(vim.trim(chunk)))
  end)

  it("keeps the popup centered with its border when zoom changes", function()
    local players = {
      { name = "Hero", is_human = true, stack = 140, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 90, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 100
    vim.o.lines = 38
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 70, current_bet = 20 })
    window.open_table()
    window.render()
    local left, right, top, bottom = current_window_margins()
    assert.is_not_nil(left)
    assert.is_true(math.abs(left - right) <= 1)
    assert.is_true(math.abs(top - bottom) <= 1)

    vim.o.columns = 74
    vim.o.lines = 28
    vim._mock.trigger_autocmd("VimResized")
    left, right, top, bottom = current_window_margins()
    assert.is_not_nil(left)
    assert.is_true(math.abs(left - right) <= 1)
    assert.is_true(math.abs(top - bottom) <= 1)
  end)

  it("keeps the popup border aligned when zooming between layouts", function()
    local players = {
      { name = "Hero", is_human = true, stack = 140, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 90, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 100
    vim.o.lines = 38
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 70, current_bet = 20 })
    window.open_table()
    window.render()
    local win_id = select(1, current_window())
    assert.is_not_nil(win_id)
    local border_id, _, thickness = border_window_for(win_id)
    assert.is_not_nil(border_id)

    local function assert_border_matches()
      local main = vim._mock.windows[win_id]
      local border = vim._mock.windows[border_id]
      local t = thickness or { top = 1, right = 1, bot = 1, left = 1 }
      assert.is_not_nil(main)
      assert.is_not_nil(border)
      local expected_width = (main.width or 0) + (t.left or 0) + (t.right or 0)
      local expected_height = (main.height or 0) + (t.top or 0) + (t.bot or 0)
      local expected_row = math.max((main.row or 0) - (t.top or 0), 0)
      local expected_col = math.max((main.col or 0) - (t.left or 0), 0)
      assert.are.equal(expected_width, border.width)
      assert.are.equal(expected_height, border.height)
      assert.are.equal(expected_row, border.row)
      assert.are.equal(expected_col, border.col)
    end

    assert_border_matches()

    vim.o.columns = 70
    vim.o.lines = 24
    vim._mock.run_deferred()
    vim._mock.run_deferred()

    assert_border_matches()

    vim.o.columns = 100
    vim.o.lines = 38
    vim._mock.run_deferred()
    vim._mock.run_deferred()

    assert_border_matches()
  end)

  it("polls for dimension changes so zooming without resize events still resizes", function()
    local players = {
      { name = "Hero", is_human = true, stack = 160, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 95, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 108
    vim.o.lines = 34
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 85, current_bet = 25 })
    window.open_table()
    window.render()
    local initial_width = current_content_width()
    assert.is_true(initial_width > 0)

    vim.o.columns = 66
    vim.o.lines = 22
    assert.are.equal(initial_width, current_content_width())

    vim._mock.run_deferred()
    vim._mock.run_deferred()

    local resized_width = current_content_width()
    assert.is_true(resized_width <= vim.o.columns - 2)
    assert.is_true(resized_width < initial_width)
    local left, right, top, bottom = current_window_margins()
    assert.is_not_nil(left)
    assert.is_true(math.abs(left - right) <= 1)
    assert.is_true(math.abs(top - bottom) <= 1)
    local lines = first_buffer_lines()
    assert.is_not_nil(find_pot_line_index(lines))
  end)

  it("keeps the table view pinned to the top when zooming between layouts", function()
    local players = {
      { name = "Hero", is_human = true, stack = 110, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 95, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 100
    vim.o.lines = 38
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 75, current_bet = 15 })
    window.open_table()
    window.render()
    local win_id = select(1, current_window())
    assert.is_not_nil(win_id)

    vim.api.nvim_win_set_cursor(win_id, { 10, 0 })

    vim.o.lines = 24
    vim._mock.run_deferred()
    vim._mock.run_deferred()

    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win_id))

    vim.api.nvim_win_set_cursor(win_id, { 10, 0 })
    vim.o.lines = 38
    vim._mock.run_deferred()
    vim._mock.run_deferred()

    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win_id))
  end)

  it("reuses the popup window when resizing via the monitor", function()
    local players = {
      { name = "Hero", is_human = true, stack = 150, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 120, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 96
    vim.o.lines = 32
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 90, current_bet = 30 })
    window.open_table()
    window.render()
    local initial_id = select(1, current_window())
    assert.is_not_nil(initial_id)

    vim.o.columns = 68
    vim.o.lines = 22
    vim._mock.run_deferred()
    vim._mock.run_deferred()

    local resized_id = select(1, current_window())
    assert.are.equal(initial_id, resized_id)
  end)

  it("does not adjust internal border thickness when resizing", function()
    local players = {
      { name = "Hero", is_human = true, stack = 150, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 120, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 96
    vim.o.lines = 32
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 80, current_bet = 20 })
    window.open_table()
    window.render()
    local popup_stub = require("plenary.popup")
    local win_id = select(1, current_window())
    assert.is_not_nil(win_id)
    local border = popup_stub._borders[win_id]
    assert.is_not_nil(border)
    border._border_win_options.border_thickness.top = 0
    border._border_win_options.border_thickness.bot = 0

    vim.o.lines = 28
    window.render()

    local thickness = popup_stub._borders[win_id]._border_win_options.border_thickness
    assert.are.equal(0, thickness.top)
    assert.are.equal(0, thickness.bot)
  end)

  it("recenters via the monitor when the editor grows without resize events", function()
    local players = {
      { name = "Hero", is_human = true, stack = 130, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 110, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 74
    vim.o.lines = 28
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 60, current_bet = 15 })
    window.open_table()
    window.render()
    local left1, right1 = current_window_margins()
    assert.is_not_nil(left1)
    assert.is_true(math.abs(left1 - right1) <= 1)

    vim.o.columns = 140
    vim.o.lines = 40
    local left_before, right_before = current_window_margins()
    assert.is_not_nil(left_before)
    assert.is_true(right_before - left_before >= 5)

    vim._mock.run_deferred()
    vim._mock.run_deferred()

    local left_after, right_after, top_after, bottom_after = current_window_margins()
    assert.is_not_nil(left_after)
    assert.is_true(math.abs(left_after - right_after) <= 1)
    assert.is_true(math.abs((top_after or 0) - (bottom_after or 0)) <= 1)
  end)

  it("renders a compact layout when the height is limited", function()
    local players = {
      {
        name = "Hero",
        is_human = true,
        stack = 70,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "A", suit = 0, rank = 14, revealed = true },
          { symbol = "K", suit = 1, rank = 13, revealed = true },
        },
      },
      {
        name = "Villain",
        stack = 120,
        bet_in_round = 0,
        hole_cards = {
          { symbol = "Q", suit = 2, rank = 12, revealed = true },
          { symbol = "Q", suit = 3, rank = 12, revealed = true },
        },
      },
    }
    vim.o.columns = 68
    vim.o.lines = 24
    match.pot = 40
    match.current_bet = 10
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 40, current_bet = 10 })
    window.open_table()
    window.render()
    local lines = first_buffer_lines()
    assert.is_nil(find_board_top_line(lines))
    local board_line = nil
    for _, line in ipairs(lines) do
      local chunk = left_chunk(line)
      if chunk:find("Board:", 1, true) then
        board_line = chunk
        break
      end
    end
    assert.is_not_nil(board_line)
    assert.is_true(board_line:find("[", 1, true) ~= nil)
    local has_opponent_header = false
    for _, line in ipairs(lines) do
      if left_chunk(line):find("Opponents:", 1, true) then
        has_opponent_header = true
        break
      end
    end
    assert.is_true(has_opponent_header)
    assert.is_true(current_content_height() <= vim.o.lines - 2)
  end)

  it("fits within the visible editor area when opened at large zoom", function()
    local players = {
      { name = "Hero", is_human = true, stack = 90, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 110, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 50
    vim.o.lines = 18
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 60, current_bet = 20 })
    window.open_table()
    window.render()
    assert.is_true(current_content_width() <= vim.o.columns - 2)
    assert.is_true(current_content_height() <= vim.o.lines - 2)
    assert.is_not_nil(find_pot_line_index(first_buffer_lines()))
    assert.is_true(current_event_width() >= 0)
  end)

  it("keeps all lines within the window width on narrow screens", function()
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    vim.o.columns = 42
    vim.o.lines = 24
    setup_match(players, match.STATE.PLAYER_TURN, { pot = 50, current_bet = 10 })
    window.open_table()
    window.render()
    local width = current_content_width()
    local max_line = 0
    for _, line in ipairs(first_buffer_lines()) do
      max_line = math.max(max_line, vim.fn.strdisplaywidth(line))
    end
    assert.is_true(max_line <= width)
  end)

  it("maps the stats key to the stats command", function()
    local utils = require("poker.utils")
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()

    local mapped = false
    for _, mapping in ipairs(vim._mock.keymaps) do
      if mapping.lhs == utils.keybindings.stats and mapping.rhs == ":PokerStats<CR>" then
        mapped = true
        break
      end
    end

    assert.is_true(mapped)
  end)

  it("updates keymaps when keybindings change", function()
    local poker = require("poker")
    local utils = require("poker.utils")
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    local original_keys = {
      primary = utils.keybindings.primary,
      secondary = utils.keybindings.secondary,
      bet = utils.keybindings.bet,
      stats = utils.keybindings.stats,
      quit = utils.keybindings.quit,
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.toggle_stats()

    local poker_buf = nil
    for _, mapping in ipairs(vim._mock.keymaps) do
      if mapping.lhs == original_keys.primary and mapping.rhs == ":PokerPrimary<CR>" then
        poker_buf = mapping.buf
        break
      end
    end
    assert.is_not_nil(poker_buf)

    local stats_buf = nil
    for _, mapping in ipairs(vim._mock.keymaps) do
      if mapping.rhs == ":PokerStats<CR>" and mapping.buf ~= poker_buf then
        stats_buf = mapping.buf
        break
      end
    end
    assert.is_not_nil(stats_buf)

    poker.set_keybindings({ primary = "x", stats = "s" })

    local function has_mapping(lhs, rhs, buf)
      for _, mapping in ipairs(vim._mock.keymaps) do
        if mapping.buf == buf and mapping.lhs == lhs and mapping.rhs == rhs then
          return true
        end
      end
      return false
    end

    assert.is_true(has_mapping("x", ":PokerPrimary<CR>", poker_buf))
    assert.is_false(has_mapping(original_keys.primary, ":PokerPrimary<CR>", poker_buf))
    assert.is_true(has_mapping("s", ":PokerStats<CR>", poker_buf))
    assert.is_true(has_mapping("s", ":PokerStats<CR>", stats_buf))
    assert.is_false(has_mapping(original_keys.stats, ":PokerStats<CR>", stats_buf))

    poker.set_keybindings(original_keys)
  end)

  it("opens a stats window with key labels", function()
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.toggle_stats()

    local labels = {
      "VPIP",
      "PFR",
      "3-Bet",
      "Fold to C-Bet",
      "AF",
      "WTSD",
      "W$SD",
      "BB Defense",
      "Flop Fold",
      "Turn Fold",
      "River Fold",
    }

    local found = false
    for _, buf in pairs(vim._mock.buffers) do
      local lines = buf.lines or {}
      local joined = table.concat(lines, "\n")
      if joined:find("VPIP", 1, true) then
        found = true
        for _, label in ipairs(labels) do
          assert.is_true(joined:find(label, 1, true) ~= nil)
        end
      end
    end

    assert.is_true(found)
  end)

  it("shows a reset hint below the stats with spacing", function()
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.toggle_stats()

    local reset_line = nil
    local prior_line = nil
    for _, buf in pairs(vim._mock.buffers) do
      local lines = buf.lines or {}
      for idx, line in ipairs(lines) do
        if line:find("Press r to reset persisted stats", 1, true) then
          reset_line = line
          prior_line = lines[idx - 1]
          break
        end
      end
      if reset_line then
        break
      end
    end

    assert.is_not_nil(reset_line)
    assert.are.equal("", vim.trim(prior_line or ""))
  end)

  it("toggles the stats window with the stats keymap", function()
    local utils = require("poker.utils")
    local players = {
      { name = "Hero", is_human = true, stack = 80, bet_in_round = 0, hole_cards = {} },
      { name = "Villain", stack = 70, bet_in_round = 0, hole_cards = {} },
    }
    setup_match(players, match.STATE.PLAYER_TURN)
    window.open_table()
    window.toggle_stats()

    local stats_buf = nil
    for id, buf in pairs(vim._mock.buffers) do
      local lines = buf.lines or {}
      local joined = table.concat(lines, "\n")
      if joined:find("VPIP", 1, true) then
        stats_buf = id
        break
      end
    end

    assert.is_not_nil(stats_buf)

    local mapped = false
    for _, mapping in ipairs(vim._mock.keymaps) do
      if mapping.buf == stats_buf and mapping.lhs == utils.keybindings.stats and mapping.rhs == ":PokerStats<CR>" then
        mapped = true
        break
      end
    end
    assert.is_true(mapped)

    local reset_mapped = false
    for _, mapping in ipairs(vim._mock.keymaps) do
      if mapping.buf == stats_buf and mapping.lhs == "r" and mapping.rhs == ":PokerResetStats<CR>" then
        reset_mapped = true
        break
      end
    end
    assert.is_true(reset_mapped)

    window.toggle_stats()

    local still_open = false
    for _, buf in pairs(vim._mock.buffers) do
      local lines = buf.lines or {}
      local joined = table.concat(lines, "\n")
      if joined:find("VPIP", 1, true) then
        still_open = true
        break
      end
    end

    assert.is_false(still_open)
  end)
end)
