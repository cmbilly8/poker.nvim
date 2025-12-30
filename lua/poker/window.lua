local popup_ok, popup = pcall(require, "plenary.popup")

local match = require("poker.match")
local utils = require("poker.utils")
local evaluator = require("poker.hand_evaluator")
local layout = require("poker.window.layout")
local event_feed = require("poker.window.event_feed")
local render = require("poker.window.render")

local PLENARY_MISSING_MESSAGE = "Poker.nvim requires plenary.nvim (nvim-lua/plenary.nvim) for its popup UI. Install it and restart Neovim."

local fn = vim.fn

local M = {
  player_panel_width = nil,
}

local poker_buf_id = nil
local poker_win_id = nil
local poker_border_win_id = nil
local stats_buf_id = nil
local stats_win_id = nil
local table_keymap_state = {}
local stats_keymap_state = {}
local resize_augroup = nil
local last_ui_columns = nil
local last_ui_lines = nil
local dimension_monitor_active = false
local render_running = false
local render_pending = false
local plenary_notified = false

local function notify_missing_plenary()
  if plenary_notified then
    return
  end
  plenary_notified = true
  local notify_fn = vim and vim.notify
  local levels = vim and vim.log and vim.log.levels or {}
  local level = levels.ERROR or levels.WARN or levels.INFO or 0
  if notify_fn then
    notify_fn(PLENARY_MISSING_MESSAGE, level, { title = "Poker" })
  else
    print(PLENARY_MISSING_MESSAGE)
  end
end

local function ensure_popup_available()
  if popup_ok and popup then
    return true
  end
  notify_missing_plenary()
  return false
end

local WINDOW_TITLE = "Xtreme Action Poker"

local DEFAULT_BORDER_CHARS = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
local KEYMAP_OPTS = { noremap = true, silent = true, nowait = true }
local CARD_INNER_WIDTH = 12
local PLAYER_PANEL_INNER_WIDTH = 58
local CARD_SPACING = 2
local CARD_BORDER_TOP = "╭" .. string.rep("─", CARD_INNER_WIDTH + 2) .. "╮"
local CARD_BORDER_BOTTOM = "╰" .. string.rep("─", CARD_INNER_WIDTH + 2) .. "╯"
local EVENT_SEP_LEFT = string.rep(" ", 2)
local EVENT_SEPARATOR_WIDTH = fn.strdisplaywidth(EVENT_SEP_LEFT)
local EVENT_FEED_WIDTH = 30
local EVENT_FEED_HEIGHT = 11
local MAX_WINDOW_WIDTH = 110
local MIN_WINDOW_HEIGHT = 22
local MAX_WINDOW_HEIGHT = 30
local WINDOW_SIDE_PADDING = 2
local BORDER_TOTAL = 2
local DIMENSION_MONITOR_INTERVAL = 150
local COMPACT_LAYOUT_HEIGHT = 24
local STATS_MIN_WIDTH = 34
local STATS_TITLE = "Player Stats"
local STATS_RESET_LABEL = "Press r to reset persisted stats"
local DEFAULT_BORDER_THICKNESS = {
  top = 1,
  right = 1,
  bot = 1,
  left = 1,
}
local function border_thickness_for(win_id)
  local thickness = DEFAULT_BORDER_THICKNESS
  if popup and popup._borders and win_id and popup._borders[win_id] then
    local opts = popup._borders[win_id]._border_win_options
    local border = opts and opts.border_thickness
    if border then
      thickness = {
        top = border.top or border[1] or thickness.top,
        right = border.right or border[2] or thickness.right,
        bot = border.bot or border.bottom or border[3] or thickness.bot,
        left = border.left or border[4] or thickness.left,
      }
    end
  end
  return thickness
end

local function resolve_border_win_id(win_id, border_id)
  if type(border_id) == "number" then
    return border_id
  end
  if popup and popup._borders and win_id and popup._borders[win_id] then
    local candidate = popup._borders[win_id].win_id
    if type(candidate) == "number" then
      return candidate
    end
  end
  return nil
end

local function sync_border_window(win_id, border_id)
  if not win_id or not border_id then
    return
  end
  if type(vim.api.nvim_win_get_config) ~= "function" then
    return
  end
  if not vim.api.nvim_win_is_valid(win_id) or not vim.api.nvim_win_is_valid(border_id) then
    return
  end
  local ok, config = pcall(vim.api.nvim_win_get_config, win_id)
  if not ok or not config then
    return
  end
  local thickness = border_thickness_for(win_id)
  local width = (config.width or 0) + (thickness.left or 0) + (thickness.right or 0)
  local height = (config.height or 0) + (thickness.top or 0) + (thickness.bot or 0)
  local row = (config.row or 0) - (thickness.top or 0)
  local col = (config.col or 0) - (thickness.left or 0)
  if row < 0 then
    row = 0
  end
  if col < 0 then
    col = 0
  end
  vim.api.nvim_win_set_config(border_id, {
    relative = config.relative or "editor",
    width = width,
    height = height,
    row = row,
    col = col,
  })
end
local ensure_buffer
local apply_buffer_keymaps
local table_keymap_specs
local stats_keymap_specs
local apply_stats_keymaps

local BOARD_CARD_INNER_WIDTH = 5
local BOARD_CARD_BORDER_TOP = "┌" .. string.rep("─", BOARD_CARD_INNER_WIDTH) .. "┐"
local BOARD_CARD_BORDER_BOTTOM = "└" .. string.rep("─", BOARD_CARD_INNER_WIDTH) .. "┘"
local BOARD_CARD_HEIGHT = 5

local layout_api = layout.setup({
  fn = fn,
  get_win_width = function()
    if poker_win_id and vim.api.nvim_win_is_valid(poker_win_id) then
      local ok, width = pcall(vim.api.nvim_win_get_width, poker_win_id)
      if ok and width then
        return width
      end
    end
    return nil
  end,
  board_card_inner_width = BOARD_CARD_INNER_WIDTH,
  card_spacing = CARD_SPACING,
  max_window_width = MAX_WINDOW_WIDTH,
  min_window_height = MIN_WINDOW_HEIGHT,
  max_window_height = MAX_WINDOW_HEIGHT,
  window_side_padding = WINDOW_SIDE_PADDING,
  border_total = BORDER_TOTAL,
})
local min_content_width = layout_api.min_content_width
local preferred_width = layout_api.preferred_width
local preferred_height = layout_api.preferred_height
local popup_dimensions = layout_api.popup_dimensions
local board_layout_for_width = layout_api.board_layout_for_width
local current_window_width = layout_api.current_window_width
local center_text = layout_api.center_text
local center_full = layout_api.center_full
local pad_to_width = layout_api.pad_to_width

local event_feed_api = event_feed.setup({
  match = match,
  utils = utils,
  fn = fn,
  pad_to_width = pad_to_width,
  current_window_width = current_window_width,
  event_feed_height = EVENT_FEED_HEIGHT,
  event_sep_left = EVENT_SEP_LEFT,
})
local build_event_lines = event_feed_api.build_event_lines
local merge_with_events = event_feed_api.merge_with_events

local render_api = render.setup({
  match = match,
  utils = utils,
  evaluator = evaluator,
  fn = fn,
  layout = layout_api,
  event_feed = event_feed_api,
  constants = {
    card_inner_width = CARD_INNER_WIDTH,
    player_panel_inner_width = PLAYER_PANEL_INNER_WIDTH,
    card_spacing = CARD_SPACING,
    card_border_top = CARD_BORDER_TOP,
    card_border_bottom = CARD_BORDER_BOTTOM,
    board_card_inner_width = BOARD_CARD_INNER_WIDTH,
    board_card_border_top = BOARD_CARD_BORDER_TOP,
    board_card_border_bottom = BOARD_CARD_BORDER_BOTTOM,
    board_card_height = BOARD_CARD_HEIGHT,
  },
})
local add_card_highlights = render_api.add_card_highlights
local apply_status_highlights = render_api.apply_status_highlights
local render_players = render_api.render_players
local action_line = render_api.action_line

local function reset_ui_bounds()
  last_ui_columns = nil
  last_ui_lines = nil
end

local function remember_ui_bounds()
  last_ui_columns = vim.o.columns
  last_ui_lines = vim.o.lines
end

local function should_resize_window(target_width, target_height)
  if not poker_win_id or not vim.api.nvim_win_is_valid(poker_win_id) then
    return true
  end
  target_width = target_width or preferred_width(vim.o.columns)
  target_height = target_height or preferred_height(vim.o.lines)
  local ok_width, current_width = pcall(vim.api.nvim_win_get_width, poker_win_id)
  local ok_height, current_height = pcall(vim.api.nvim_win_get_height, poker_win_id)
  if not ok_width or not ok_height or not current_width or not current_height then
    return true
  end
  if current_width ~= target_width or current_height ~= target_height then
    return true
  end
  if last_ui_columns ~= vim.o.columns or last_ui_lines ~= vim.o.lines then
    return true
  end
  return false
end

local function apply_popup_window(popup_width, popup_height, row, col)
  if not ensure_popup_available() then
    return false
  end
  ensure_buffer()
  local line = (row or 0) + 1
  local column = (col or 0) + 1
  if poker_win_id and vim.api.nvim_win_is_valid(poker_win_id) then
    popup.move(poker_win_id, {
      line = line,
      col = column,
      width = popup_width,
      height = popup_height,
      minwidth = popup_width,
      minheight = popup_height,
    })
  else
    poker_win_id, poker_border_win_id = popup.create(poker_buf_id, {
      title = WINDOW_TITLE,
      highlight = "PokerWindow",
      line = line,
      col = column,
      width = popup_width,
      height = popup_height,
      minwidth = popup_width,
      minheight = popup_height,
      borderchars = DEFAULT_BORDER_CHARS,
    })
  end
  poker_border_win_id = resolve_border_win_id(poker_win_id, poker_border_win_id)
  sync_border_window(poker_win_id, poker_border_win_id)
  remember_ui_bounds()
  return true
end












ensure_buffer = function()
  if not poker_buf_id or not vim.api.nvim_buf_is_valid(poker_buf_id) then
    poker_buf_id = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_option(poker_buf_id, "modifiable", false)
    vim.api.nvim_buf_set_option(poker_buf_id, "buftype", "nofile")
    vim.api.nvim_buf_set_option(poker_buf_id, "bufhidden", "hide")
  end
end

local function ensure_stats_buffer()
  if not stats_buf_id or not vim.api.nvim_buf_is_valid(stats_buf_id) then
    stats_buf_id = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_option(stats_buf_id, "modifiable", false)
    vim.api.nvim_buf_set_option(stats_buf_id, "buftype", "nofile")
    vim.api.nvim_buf_set_option(stats_buf_id, "bufhidden", "hide")
  end
end

local function format_percent(value)
  if value == nil then
    return "n/a"
  end
  return string.format("%.1f%%", value * 100)
end

local function format_af(value)
  if value == nil then
    return "n/a"
  end
  if value == math.huge then
    return "Inf"
  end
  return string.format("%.2f", value)
end

local function current_human_id()
  local players = match.players
  if type(match.get_players) == "function" then
    players = match.get_players()
  end
  for _, player in ipairs(players or {}) do
    if player.is_human and player.id ~= nil then
      return player.id
    end
  end
  if players and players[1] and players[1].id ~= nil then
    return players[1].id
  end
  return 1
end

local function build_stats_lines()
  local player_id = current_human_id()
  local stats = match.get_player_stats(player_id)
  local rows = {
    { "VPIP", format_percent(stats.vpip) },
    { "PFR", format_percent(stats.pfr) },
    { "3-Bet %", format_percent(stats.three_bet) },
    { "Fold to C-Bet", format_percent(stats.fold_to_cbet) },
    { "AF", format_af(stats.aggression_factor) },
    { "WTSD", format_percent(stats.wtsd) },
    { "W$SD", format_percent(stats.wsd) },
    { "BB Defense", format_percent(stats.bb_defense) },
    { "Flop Fold %", format_percent(stats.fold_flop) },
    { "Turn Fold %", format_percent(stats.fold_turn) },
    { "River Fold %", format_percent(stats.fold_river) },
  }

  local label_width = 0
  for _, row in ipairs(rows) do
    label_width = math.max(label_width, #row[1])
  end

  local lines = { "" }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.format("%-" .. label_width .. "s  %s", row[1] .. ":", row[2])
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = STATS_RESET_LABEL
  return lines
end

local function stats_popup_dimensions(lines)
  local width = STATS_MIN_WIDTH
  for _, line in ipairs(lines or {}) do
    width = math.max(width, fn.strdisplaywidth(line))
  end
  local max_columns = math.max(1, vim.o.columns or 1)
  local max_lines = math.max(1, vim.o.lines or 1)
  if width > max_columns - BORDER_TOTAL then
    width = math.max(max_columns - BORDER_TOTAL, 1)
  end
  local height = math.max(#(lines or {}), 1)
  if height > max_lines - BORDER_TOTAL then
    height = math.max(max_lines - BORDER_TOTAL, 1)
  end
  local total_width = width + BORDER_TOTAL
  local total_height = height + BORDER_TOTAL
  local row = math.max(0, math.floor((max_lines - total_height) / 2))
  local col = math.max(0, math.floor((max_columns - total_width) / 2))
  return width, height, row, col
end

local function render_stats_window()
  if not stats_buf_id or not stats_win_id or not vim.api.nvim_win_is_valid(stats_win_id) then
    return
  end
  local lines = build_stats_lines()
  local width, height, row, col = stats_popup_dimensions(lines)
  popup.move(stats_win_id, {
    line = row + 1,
    col = col + 1,
    width = width,
    height = height,
    minwidth = width,
    minheight = height,
  })
  vim.api.nvim_buf_set_option(stats_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(stats_buf_id, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(stats_buf_id, "modifiable", false)
end

local function clear_buffer_keymaps(buf_id, keymaps)
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then
    return
  end
  if type(vim.api.nvim_buf_del_keymap) ~= "function" then
    return
  end
  for _, lhs in ipairs(keymaps or {}) do
    pcall(vim.api.nvim_buf_del_keymap, buf_id, "n", lhs)
  end
end

apply_buffer_keymaps = function(buf_id, specs, existing)
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then
    return {}
  end
  clear_buffer_keymaps(buf_id, existing)
  local applied = {}
  for _, spec in ipairs(specs or {}) do
    if spec.lhs then
      vim.api.nvim_buf_set_keymap(buf_id, spec.mode or "n", spec.lhs, spec.rhs, KEYMAP_OPTS)
      applied[#applied + 1] = spec.lhs
    end
  end
  return applied
end

table_keymap_specs = function()
  return {
    { lhs = utils.keybindings.primary, rhs = ":PokerPrimary<CR>" },
    { lhs = utils.keybindings.secondary, rhs = ":PokerSecondary<CR>" },
    { lhs = utils.keybindings.bet, rhs = ":PokerBet<CR>" },
    { lhs = utils.keybindings.stats, rhs = ":PokerStats<CR>" },
    { lhs = utils.keybindings.quit, rhs = ":PokerQuit<CR>" },
  }
end

stats_keymap_specs = function()
  return {
    { lhs = utils.keybindings.stats, rhs = ":PokerStats<CR>" },
    { lhs = "r", rhs = ":PokerResetStats<CR>" },
  }
end

apply_stats_keymaps = function()
  stats_keymap_state = apply_buffer_keymaps(stats_buf_id, stats_keymap_specs(), stats_keymap_state)
end

local function open_stats_window()
  if not ensure_popup_available() then
    return
  end
  ensure_stats_buffer()
  local lines = build_stats_lines()
  local width, height, row, col = stats_popup_dimensions(lines)
  if stats_win_id and vim.api.nvim_win_is_valid(stats_win_id) then
    popup.move(stats_win_id, {
      line = row + 1,
      col = col + 1,
      width = width,
      height = height,
      minwidth = width,
      minheight = height,
    })
  else
    stats_win_id, _ = popup.create(stats_buf_id, {
      title = STATS_TITLE,
      highlight = "PokerWindow",
      line = row + 1,
      col = col + 1,
      width = width,
      height = height,
      minwidth = width,
      minheight = height,
      borderchars = DEFAULT_BORDER_CHARS,
    })
  end
  vim.api.nvim_buf_set_option(stats_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(stats_buf_id, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(stats_buf_id, "modifiable", false)
  apply_stats_keymaps()
end

local function close_stats_window()
  if stats_win_id and vim.api.nvim_win_is_valid(stats_win_id) then
    pcall(function()
      vim.api.nvim_win_close(stats_win_id, true)
    end)
  end
  if stats_buf_id and vim.api.nvim_buf_is_valid(stats_buf_id) then
    pcall(function()
      vim.api.nvim_buf_delete(stats_buf_id, { force = true })
    end)
  end
  stats_win_id = nil
  stats_buf_id = nil
  stats_keymap_state = {}
end





























local function apply_window_dimensions(force)
  if poker_buf_id == nil then
    return false
  end
  local popup_width, popup_height, row, col = popup_dimensions()
  if not force and not should_resize_window(popup_width, popup_height) then
    return false
  end
  return apply_popup_window(popup_width, popup_height, row, col)
end

local function dimension_monitor_tick()
  if not dimension_monitor_active then
    return
  end
  local changed = false
  if poker_buf_id ~= nil then
    changed = apply_window_dimensions(false)
  end
  if changed then
    M.render()
  end
  if dimension_monitor_active then
    vim.defer_fn(dimension_monitor_tick, DIMENSION_MONITOR_INTERVAL)
  end
end

local function start_dimension_monitor()
  if dimension_monitor_active then
    return
  end
  dimension_monitor_active = true
  vim.defer_fn(dimension_monitor_tick, DIMENSION_MONITOR_INTERVAL)
end

local function stop_dimension_monitor()
  dimension_monitor_active = false
end

local function teardown_resize_autocmd()
  if resize_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, resize_augroup)
    resize_augroup = nil
  end
end

local function handle_resize()
  if poker_buf_id == nil then
    return
  end
  local changed = apply_window_dimensions(true)
  if changed then
    M.render()
  end
end

local function setup_resize_autocmd()
  teardown_resize_autocmd()
  resize_augroup = vim.api.nvim_create_augroup("PokerWindowResize", { clear = true })
  for _, event in ipairs({ "VimResized", "WinResized" }) do
    vim.api.nvim_create_autocmd(event, {
      group = resize_augroup,
      callback = handle_resize,
    })
  end
  vim.api.nvim_create_autocmd("OptionSet", {
    group = resize_augroup,
    pattern = { "columns", "lines" },
    callback = handle_resize,
  })
end

M.handle_resize = handle_resize

local function apply_table_keymaps()
  table_keymap_state = apply_buffer_keymaps(poker_buf_id, table_keymap_specs(), table_keymap_state)
end

function M.apply_keybindings()
  apply_table_keymaps()
  apply_stats_keymaps()
end

function M.open_table()
  if not ensure_popup_available() then
    return
  end
  if poker_buf_id ~= nil then
    M.destroy()
  end
  match.set_on_change(M.render)
  ensure_buffer()
  local popup_width, popup_height, row, col = popup_dimensions()
  apply_popup_window(popup_width, popup_height, row, col)
  setup_resize_autocmd()
  start_dimension_monitor()
  vim.api.nvim_buf_set_option(poker_buf_id, "modifiable", false)
  apply_table_keymaps()
  M.render()
end

function M.toggle_stats()
  if stats_win_id and vim.api.nvim_win_is_valid(stats_win_id) then
    close_stats_window()
  else
    open_stats_window()
  end
end

function M.reset_stats()
  if match.reset_stats then
    match.reset_stats()
  else
    match.reset_scores()
  end
  render_stats_window()
end

function M.update_title()
  -- No-op: window title remains static.
end

function M.destroy()
  match.set_on_change(nil)
  teardown_resize_autocmd()
  stop_dimension_monitor()
  close_stats_window()
  if poker_win_id and vim.api.nvim_win_is_valid(poker_win_id) then
    pcall(function()
      vim.api.nvim_win_close(poker_win_id, true)
    end)
    poker_win_id = nil
  end
  if poker_border_win_id and vim.api.nvim_win_is_valid(poker_border_win_id) then
    pcall(function()
      vim.api.nvim_win_close(poker_border_win_id, true)
    end)
  end
  poker_border_win_id = nil
  if poker_buf_id and vim.api.nvim_buf_is_valid(poker_buf_id) then
    pcall(function()
      vim.api.nvim_buf_delete(poker_buf_id, { force = true })
    end)
  end
  poker_buf_id = nil
  table_keymap_state = {}
  reset_ui_bounds()
end

local function render_once()
  if poker_buf_id == nil then
    return
  end
  apply_window_dimensions(false)
  local players = match.get_players()
  local board = match.get_board()
  local reveal_all = match.current_state == match.STATE.HAND_OVER
  local lines = {}
  local status_highlights = {}
  local content_width = current_window_width()
  local available_height = preferred_height(vim.o.lines)
  local use_compact_layout = available_height <= COMPACT_LAYOUT_HEIGHT
  local separator_width = EVENT_SEPARATOR_WIDTH
  local required_left = min_content_width()
  local max_event = math.max(content_width - separator_width - required_left, 0)
  local event_width = math.min(EVENT_FEED_WIDTH, max_event)
  local left_width = content_width
  local event_feed = nil
  if event_width > 0 then
    left_width = content_width - event_width - separator_width
    event_feed = {
      lines = build_event_lines(event_width),
      width = event_width,
      index = 1,
    }
  end
  local actions = action_line()
  local layout_info = render_players(
    lines,
    players,
    reveal_all,
    content_width,
    status_highlights,
    board,
    {
      left_width = left_width,
      event_feed = event_feed,
      action_text = actions,
      player_panel_width = M.player_panel_width or PLAYER_PANEL_INNER_WIDTH,
      compact = use_compact_layout,
    }
  )
  local merged_lines
  if event_feed then
    local min_start_line = (layout_info and layout_info.last_opponent_line or 0) + 2
    local desired_height = math.max(#lines - min_start_line + 1, 0)
    event_feed.lines = build_event_lines(event_width, desired_height)
    merged_lines = merge_with_events(lines, event_feed, left_width, min_start_line)
  else
    merged_lines = lines
  end
  add_card_highlights(merged_lines, status_highlights)
  vim.api.nvim_buf_set_option(poker_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(poker_buf_id, 0, -1, true, merged_lines)
  vim.api.nvim_buf_set_option(poker_buf_id, "modifiable", false)
  apply_status_highlights(poker_buf_id, status_highlights)
  if poker_win_id and vim.api.nvim_win_is_valid(poker_win_id) and vim.api.nvim_win_set_cursor then
    pcall(vim.api.nvim_win_set_cursor, poker_win_id, { 1, 0 })
  end
  render_stats_window()
  M.update_title()
end

function M.render()
  if poker_buf_id == nil then
    return
  end
  if render_running then
    render_pending = true
    return
  end
  render_running = true
  repeat
    render_pending = false
    render_once()
  until not render_pending
  render_running = false
end

return M
