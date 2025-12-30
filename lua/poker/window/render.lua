local M = {}

function M.setup(ctx)
  local match = ctx.match
  local utils = ctx.utils
  local evaluator = ctx.evaluator
  local fn = ctx.fn
  local layout = ctx.layout
  local event_feed = ctx.event_feed
  local constants = ctx.constants or {}

  local card_inner_width = constants.card_inner_width or 12
  local card_spacing = constants.card_spacing or 2
  local card_border_top = constants.card_border_top or "╭" .. string.rep("─", card_inner_width + 2) .. "╮"
  local card_border_bottom = constants.card_border_bottom or "╰" .. string.rep("─", card_inner_width + 2) .. "╯"
  local board_card_inner_width = constants.board_card_inner_width or 5
  local board_card_height = constants.board_card_height or 5

  local current_window_width = layout.current_window_width
  local center_text = layout.center_text
  local center_full = layout.center_full
  local pad_to_width = layout.pad_to_width
  local board_layout_for_width = layout.board_layout_for_width
  local append_left_with_event = event_feed.append_left_with_event
  local append_remaining_events = event_feed.append_remaining_events

  local STATUS_HIGHLIGHT_NS = vim.api.nvim_create_namespace("PokerStatus")
  local STATUS_HIGHLIGHT_GROUPS = {
    fold = { group = "PokerStatusFold", color = "#ff6b6b" },
    check = { group = "PokerStatusCheck", color = "#ffd166" },
    bet = { group = "PokerStatusBet", color = "#06d6a0" },
    raise = { group = "PokerStatusBet", color = "#06d6a0" },
    call = { group = "PokerStatusCall", color = "#118ab2" },
    win = { group = "PokerStatusWin", color = "#06d6a0" },
  }
  local STATUS_HIGHLIGHTS_DEFINED = false

  local CARD_RED_HIGHLIGHT_GROUP = "PokerCardRed"
  local PLAYER_WIN_BORDER_GROUP = "PokerPlayerWinBorder"
  local PLAYER_FOLD_BORDER_GROUP = "PokerPlayerFoldBorder"
  local PLAYER_ACTIVE_BORDER_GROUP = "PokerPlayerActiveBorder"
  local RED_SUIT_SYMBOLS = { "♥", "♡", "♦", "♢" }
  local BORDER_GLYPHS = {
    ["┌"] = true,
    ["┐"] = true,
    ["└"] = true,
    ["┘"] = true,
    ["╭"] = true,
    ["╮"] = true,
    ["╰"] = true,
    ["╯"] = true,
    ["│"] = true,
    ["─"] = true,
  }
  local split_action_tokens
  local wrap_action_text

  local function ensure_status_highlight_groups()
    if STATUS_HIGHLIGHTS_DEFINED then
      return
    end
    for _, meta in pairs(STATUS_HIGHLIGHT_GROUPS) do
      if meta.group and meta.color then
        vim.api.nvim_set_hl(0, meta.group, { default = true, fg = meta.color })
      end
    end
    vim.api.nvim_set_hl(0, CARD_RED_HIGHLIGHT_GROUP, { default = true, fg = "#ff6b6b" })
    vim.api.nvim_set_hl(0, PLAYER_WIN_BORDER_GROUP, { default = true, fg = "#06d6a0" })
    vim.api.nvim_set_hl(0, PLAYER_FOLD_BORDER_GROUP, { default = true, fg = "#ff6b6b" })
    vim.api.nvim_set_hl(0, PLAYER_ACTIVE_BORDER_GROUP, { default = true, fg = "#ffd166" })
    STATUS_HIGHLIGHTS_DEFINED = true
  end

  local function normalize_status_label(status)
    if not status or status == "" then
      return nil
    end
    local label = status:lower()
    label = label:gsub("%+ai", "")
    label = label:gsub("%*", "")
    label = label:gsub("%s", "")
    local token = label:match("^([%a]+)")
    return token
  end

  local function status_highlight_group(status)
    local token = normalize_status_label(status)
    if not token then
      return nil
    end
    local meta = STATUS_HIGHLIGHT_GROUPS[token]
    if not meta then
      return nil
    end
    return meta.group
  end

  local function is_winning_status(status)
    return normalize_status_label(status) == "win"
  end

  local function add_line_highlight(highlights, line_index, line_text, status)
    local group = status_highlight_group(status)
    if not group or not line_text or line_text == "" then
      return
    end
    local start_col = line_text:find(status, 1, true)
    if not start_col then
      local token = normalize_status_label(status)
      if not token then
        return
      end
      start_col = line_text:lower():find(token, 1, true)
      if not start_col then
        return
      end
      status = line_text:sub(start_col, start_col + #token - 1)
    end
    local end_col = start_col - 1 + #status
    highlights[#highlights + 1] = {
      line = line_index - 1,
      col_start = start_col - 1,
      col_end = end_col,
      group = group,
    }
  end

  local function add_card_highlights(lines, highlights)
    for idx, text in ipairs(lines) do
      if text and text ~= "" then
        for _, suit in ipairs(RED_SUIT_SYMBOLS) do
          local search_start = 1
          while true do
            local start_col = text:find(suit, search_start, true)
            if not start_col then
              break
            end
            highlights[#highlights + 1] = {
              line = idx - 1,
              col_start = start_col - 1,
              col_end = start_col - 1 + #suit,
              group = CARD_RED_HIGHLIGHT_GROUP,
            }
            search_start = start_col + #suit
          end
        end
      end
    end
  end

  local function apply_status_highlights(buf_id, highlights)
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
      return
    end
    ensure_status_highlight_groups()
    vim.api.nvim_buf_clear_namespace(buf_id, STATUS_HIGHLIGHT_NS, 0, -1)
    for _, entry in ipairs(highlights or {}) do
      if entry.group and entry.line ~= nil and entry.col_start ~= nil and entry.col_end ~= nil then
        pcall(vim.api.nvim_buf_add_highlight, buf_id, STATUS_HIGHLIGHT_NS, entry.group, entry.line, entry.col_start, entry.col_end)
      end
    end
  end

  local function add_border_highlights(lines, highlights, start_line, end_line, group, limit_width)
    if not group or not lines then
      return
    end
    start_line = math.max(start_line or 1, 1)
    end_line = math.min(end_line or #lines, #lines)
    for line_idx = start_line, end_line do
      local text = lines[line_idx]
      if text and text ~= "" then
        local glyphs = fn.split(text, [[\zs]])
        local byte_index = 0
        local used_width = 0
        for _, glyph in ipairs(glyphs) do
          local glyph_display = fn.strdisplaywidth(glyph)
          if limit_width and used_width >= limit_width then
            break
          end
          if limit_width and used_width + glyph_display > limit_width then
            break
          end
          local glyph_len = #glyph
          if BORDER_GLYPHS[glyph] then
            highlights[#highlights + 1] = {
              line = line_idx - 1,
              col_start = byte_index,
              col_end = byte_index + glyph_len,
              group = group,
            }
          end
          byte_index = byte_index + glyph_len
          used_width = used_width + glyph_display
        end
      end
    end
  end

  local function remove_highlights_in_range(highlights, group, start_line, end_line)
    if not highlights or not group then
      return
    end
    local start_idx = math.max((start_line or 1) - 1, 0)
    local end_idx = math.max((end_line or 0) - 1, start_idx)
    local filtered = {}
    for _, entry in ipairs(highlights) do
      local line = entry.line or -1
      if not (entry.group == group and line >= start_idx and line <= end_idx) then
        filtered[#filtered + 1] = entry
      end
    end
    if #filtered ~= #highlights then
      return filtered
    end
    return highlights
  end

  local function player_position_suffix(index)
    local tokens = {}
    if match.button_index and match.button_index == index then
      tokens[#tokens + 1] = "[D]"
    end
    if match.small_blind_index and match.small_blind_index == index then
      tokens[#tokens + 1] = "[SB]"
    end
    if match.big_blind_index and match.big_blind_index == index then
      tokens[#tokens + 1] = "[BB]"
    end
    if #tokens == 0 then
      return ""
    end
    return " " .. table.concat(tokens, " ")
  end

  local function player_best_hand_summary(player, board)
    if not player then
      return nil
    end
    local combined = {}
    if player.hole_cards then
      for _, card in ipairs(player.hole_cards) do
        combined[#combined + 1] = card
      end
    end
    if board then
      for _, card in ipairs(board) do
        combined[#combined + 1] = card
      end
    end
    if #combined == 0 then
      return nil
    end
    if #combined >= 5 then
      local score = evaluator.best_hand(combined)
      if score then
        local name = utils.hand_name(score)
        if name then
          return name
        end
      end
      return utils.hand_name_from_category(0)
    else
      local ranks = {}
      for _, card in ipairs(combined) do
        if card.rank then
          ranks[card.rank] = (ranks[card.rank] or 0) + 1
          if ranks[card.rank] >= 2 then
            return utils.hand_name_from_category(1)
          end
        end
      end
      return utils.hand_name_from_category(0)
    end
  end

  local function format_cards(cards, reveal)
    if not cards or #cards == 0 then
      return "--"
    end
    local parts = {}
    for _, card in ipairs(cards) do
      if reveal then
        parts[#parts + 1] = string.format("[%s%s]", card.symbol, utils.get_suit(card))
      else
        parts[#parts + 1] = "[??]"
      end
    end
    return table.concat(parts, " ")
  end

  local function clone_cards_for_display(cards, force_reveal)
    if not cards then
      return nil
    end
    local clones = {}
    for _, card in ipairs(cards) do
      clones[#clones + 1] = {
        symbol = card.symbol,
        suit = card.suit,
        rank = card.rank,
        revealed = force_reveal or card.revealed,
      }
    end
    return clones
  end

  local function status_label_and_amount(player)
    if not player then
      return "", nil
    end
    local status
    if player.folded then
      status = "fold"
    elseif player.last_action and player.last_action ~= "" then
      status = player.last_action
    else
      status = "wait"
    end
    status = vim.trim(status:gsub("%s*%(all%-in%)", ""))
    if status == "" then
      status = player.folded and "fold" or "wait"
    end
    local amount = status:match("^call (%d+)")
    if amount then
      return "call", amount
    end
    amount = status:match("^bet (%d+)")
    if amount then
      return "bet", amount
    end
    amount = status:match("^raise to (%d+)")
    if amount then
      return "raise", amount
    end
    amount = status:match("^posts small blind (%d+)")
    if amount then
      return "SB", amount
    end
    amount = status:match("^posts big blind (%d+)")
    if amount then
      return "BB", amount
    end
    amount = status:match("^won (%d+)")
    if amount then
      return "win", amount
    end
    if status == "won" then
      return "win", nil
    end
    if status == "waiting" or status == "wait" then
      return "", nil
    end
    if status == "folded" then
      return "fold", nil
    end
    return status, nil
  end

  local function pot_amount_from_status(label, amount)
    if not amount or not label or label == "" then
      return nil
    end
    local lower = label:lower()
    if lower == "call" or lower == "bet" or lower == "raise" or lower == "sb" or lower == "bb" then
      return amount
    end
    return nil
  end

  local function pot_contribution_amount(player)
    local label, amount = status_label_and_amount(player)
    return pot_amount_from_status(label, amount)
  end

  local function short_status(player)
    local label = status_label_and_amount(player)
    return label or ""
  end

  local function player_visible_cards(cards)
    if not cards or #cards == 0 then
      return {}
    end
    return clone_cards_for_display(cards, true)
  end

  local function card_token_for_display(card, reveal)
    if not card then
      return "[??]"
    end
    local display = card
    if reveal then
      display = {
        symbol = card.symbol,
        suit = card.suit,
        rank = card.rank,
        revealed = true,
      }
    end
    if not display.revealed then
      return "[??]"
    end
    local suit = utils.get_suit(display)
    return string.format("[%s%s]", display.symbol or "?", suit)
  end

  local function compact_board_line(board, reveal_all)
    local tokens = {}
    for i = 1, 5 do
      local card = board and board[i] or nil
      local show = reveal_all or (card and card.revealed)
      tokens[#tokens + 1] = card_token_for_display(card, show)
    end
    return table.concat(tokens, " ")
  end

  local function truncate_for_card(text, inner_width)
    text = text or ""
    inner_width = inner_width or card_inner_width
    local glyphs = fn.split(text, [[\zs]])
    local builder = {}
    local width = 0
    for _, glyph in ipairs(glyphs) do
      local glyph_width = fn.strdisplaywidth(glyph)
      if width + glyph_width > inner_width then
        break
      end
      builder[#builder + 1] = glyph
      width = width + glyph_width
    end
    return table.concat(builder), width
  end

  local function card_line(text, align, inner_width)
    inner_width = inner_width or card_inner_width
    local truncated, width = truncate_for_card(text, inner_width)
    local padding = inner_width - width
    if padding < 0 then
      padding = 0
    end
    if align == "center" then
      local left = math.floor(padding / 2)
      local right = padding - left
      return "│ " .. string.rep(" ", left) .. truncated .. string.rep(" ", right) .. " │"
    end
    return "│ " .. truncated .. string.rep(" ", padding) .. " │"
  end

  local function board_card_line(text, align, inner_width)
    inner_width = inner_width or board_card_inner_width
    local truncated, width = truncate_for_card(text, inner_width)
    local padding = math.max(inner_width - width, 0)
    local left = 0
    local right = padding
    if align == "center" then
      left = math.floor(padding / 2)
      right = padding - left
    elseif align == "right" then
      left = padding
      right = 0
    end
    return string.format("│%s%s%s│", string.rep(" ", left), truncated, string.rep(" ", right))
  end

  local function build_board_card(card, inner_width)
    inner_width = inner_width or board_card_inner_width
    local top = "┌" .. string.rep("─", inner_width) .. "┐"
    local bottom = "└" .. string.rep("─", inner_width) .. "┘"
    if not card or not card.revealed then
      local blank = string.rep(" ", inner_width + 2)
      return {
        blank,
        blank,
        blank,
        blank,
        blank,
      }
    end
    local rank = card.symbol or "?"
    local suit = utils.get_suit(card)
    return {
      top,
      board_card_line(rank, "left", inner_width),
      board_card_line(suit, "center", inner_width),
      board_card_line(rank, "right", inner_width),
      bottom,
    }
  end

  local function append_card_blocks(lines, blocks, width, filler_height, spacing)
    filler_height = filler_height or board_card_height
    spacing = spacing or card_spacing
    width = math.max(width or 0, 0)
    if not blocks or #blocks == 0 then
      for _ = 1, filler_height do
        lines[#lines + 1] = center_full("", width)
      end
      return
    end
    local spacing_text = string.rep(" ", spacing)
    local card_height = #blocks[1]
    for row = 1, card_height do
      local row_segments = {}
      for _, block in ipairs(blocks) do
        row_segments[#row_segments + 1] = block[row]
      end
      local row_text = table.concat(row_segments, spacing_text)
      lines[#lines + 1] = center_full(row_text, width)
    end
  end

  local function build_board_rows(board, width, board_layout)
    board_layout = board_layout or { inner_width = board_card_inner_width, spacing = card_spacing }
    local rows = {}
    local blocks = {}
    for i = 1, 5 do
      local card = board and board[i] or nil
      blocks[#blocks + 1] = build_board_card(card, board_layout.inner_width)
    end
    append_card_blocks(rows, blocks, width, board_card_height, board_layout.spacing)
    return rows
  end

  local function build_player_rows(hole_cards, width, board_layout)
    board_layout = board_layout or { inner_width = board_card_inner_width, spacing = card_spacing }
    local rows = {}
    local blocks = {}
    if hole_cards and #hole_cards > 0 then
      for _, card in ipairs(hole_cards) do
        local display = {
          symbol = card.symbol,
          suit = card.suit,
          revealed = true,
        }
        blocks[#blocks + 1] = build_board_card(display, board_layout.inner_width)
      end
    end
    while #blocks < 2 do
      blocks[#blocks + 1] = build_board_card(nil, board_layout.inner_width)
    end
    append_card_blocks(rows, blocks, width, board_card_height, board_layout.spacing)
    return rows
  end

  local function build_opponent_card(player, reveal_all, is_active, index)
    local reveal = reveal_all
    local stack = player.stack or 0
    local status_label, status_amount = status_label_and_amount(player)
    local status = status_label or ""
    if player.all_in and status ~= "" then
      status = status .. "+AI"
    elseif player.all_in then
      status = "AI"
    end
    if is_active and not player.folded then
      status = status ~= "" and (status .. "*") or "*"
    end
    local pot_amount = pot_amount_from_status(status_label, status_amount)
    local player_won = is_winning_status(status)
    local suffix = player_position_suffix(index)
    local display_name = (player.name or "Opponent") .. suffix
    local lines = {
      card_border_top,
      card_line(display_name, "center"),
      card_line(format_cards(player.hole_cards, reveal), "center"),
      card_line(string.format("stack: %d", stack)),
      card_line(status, "center"),
      card_border_bottom,
    }
    local highlights = {}
    if status and status ~= "" then
      highlights[#highlights + 1] = { row = 6, text = status, group = status_highlight_group(status) }
    end
    local border_group = nil
    if player_won then
      border_group = PLAYER_WIN_BORDER_GROUP
    elseif player.folded then
      border_group = PLAYER_FOLD_BORDER_GROUP
    elseif is_active then
      border_group = PLAYER_ACTIVE_BORDER_GROUP
    end
    return {
      lines = lines,
      highlights = highlights,
      border_group = border_group,
      amount = pot_amount,
    }
  end

  local function append_opponent_cards(lines, opponents, reveal_all, width, highlights)
    if not opponents or #opponents == 0 then
      return
    end
    width = width or current_window_width()
    local show_turn = match.current_state ~= match.STATE.HAND_OVER
    local active_index = match.current_player_index
    local cards = {}
    for _, entry in ipairs(opponents) do
      local is_active = show_turn and active_index == entry.index
      cards[#cards + 1] = build_opponent_card(entry.player, reveal_all, is_active, entry.index)
    end
    local card_width = card_inner_width + 4
    local spacing = string.rep(" ", card_spacing)
    local spacing_len = #spacing
    local available_width = math.max((width or vim.o.columns) - 4, card_width)
    local per_row = math.max(1, math.floor((available_width + card_spacing) / (card_width + card_spacing)))
    local card_height = #cards[1].lines
    for start = 1, #cards, per_row do
      local chunk = {}
      for idx = start, math.min(#cards, start + per_row - 1) do
        chunk[#chunk + 1] = cards[idx]
      end
      for row = 1, card_height do
        local row_segments = {}
        local block_offsets = {}
        local running = 0
        for idx, block in ipairs(chunk) do
          local text = block.lines[row]
          row_segments[#row_segments + 1] = text
          block_offsets[idx] = running
          running = running + #text
          if idx < #chunk then
            running = running + spacing_len
          end
        end
        local row_text = table.concat(row_segments, spacing)
        local centered = center_text(row_text, width)
        lines[#lines + 1] = centered
        local padding = #centered - #row_text
        if highlights then
          for idx, block in ipairs(chunk) do
            if block.highlights then
              for _, hl in ipairs(block.highlights) do
                if hl.group and hl.row == row then
                  local relative = block.lines[row]:find(hl.text, 1, true)
                  if relative then
                    local col_start = padding + block_offsets[idx] + relative - 1
                    local col_end = col_start + #hl.text
                    highlights[#highlights + 1] = {
                      line = #lines - 1,
                      col_start = col_start,
                      col_end = col_end,
                      group = hl.group,
                    }
                  end
                end
              end
            end
            if block.border_group then
              local glyphs = fn.split(block.lines[row], [[\zs]])
              local byte_index = 0
              for _, glyph in ipairs(glyphs) do
                local glyph_len = #glyph
                if BORDER_GLYPHS[glyph] then
                  local col_start = padding + block_offsets[idx] + byte_index
                  local col_end = col_start + glyph_len
                  highlights[#highlights + 1] = {
                    line = #lines - 1,
                    col_start = col_start,
                    col_end = col_end,
                    group = block.border_group,
                  }
                end
                byte_index = byte_index + glyph_len
              end
            end
          end
        end
      end
      local amount_segments = {}
      for _, block in ipairs(chunk) do
        amount_segments[#amount_segments + 1] = center_full(block.amount or "", card_width)
      end
      local amount_row = center_text(table.concat(amount_segments, spacing), width)
      lines[#lines + 1] = amount_row
      if start + per_row - 1 < #cards then
        lines[#lines + 1] = ""
      end
    end
  end

  local function render_user_row(lines, user_entry, width, highlights, board, layout_config)
    if not user_entry then
      return
    end
    layout_config = layout_config or {}
    local player = user_entry.player
    local stack = player.stack or 0
    local status = short_status(player)
    local player_won = is_winning_status(status)
    local suffix = player_position_suffix(user_entry.index)
    local header = (player.name or "Player") .. suffix
    local best_hand_text = player_best_hand_summary(player, board)
    if best_hand_text and best_hand_text ~= "" then
      header = string.format("%s: %s", header, best_hand_text)
    else
      header = header .. ":"
    end
    local left_width = layout_config.left_width or width
    local feed = layout_config.event_feed
    local desired_inner = layout_config.player_panel_width or (left_width - 2)
    local inner_width = math.max(0, math.min(desired_inner, left_width - 2))
    local panel_lines = {}
    panel_lines[#panel_lines + 1] = center_text(header, inner_width)
    local card_rows = build_player_rows(player.hole_cards, inner_width, layout_config.board_layout)
    for _, row in ipairs(card_rows) do
      panel_lines[#panel_lines + 1] = row
    end
    panel_lines[#panel_lines + 1] = center_text(string.format("Stack: %d", stack), inner_width)
    if layout_config.action_text and layout_config.action_text ~= "" then
      panel_lines[#panel_lines + 1] = ""
      local wrapped = wrap_action_text(layout_config.action_text, inner_width)
      for _, action in ipairs(wrapped) do
        panel_lines[#panel_lines + 1] = center_text(action, inner_width)
      end
    end

    local top_border = "╭" .. string.rep("─", inner_width) .. "╮"
    local bottom_border = "╰" .. string.rep("─", inner_width) .. "╯"
    local card_start = #lines + 1
    append_left_with_event(lines, center_text(top_border, left_width), feed, left_width)
    for _, row in ipairs(panel_lines) do
      local padded = pad_to_width(row, inner_width)
      append_left_with_event(lines, center_text("│" .. padded .. "│", left_width), feed, left_width)
    end
    append_left_with_event(lines, center_text(bottom_border, left_width), feed, left_width)
    local card_end = #lines
    if highlights then
      local filtered = remove_highlights_in_range(highlights, PLAYER_ACTIVE_BORDER_GROUP, card_start, card_end)
      if filtered ~= highlights then
        for i = 1, #highlights do
          highlights[i] = nil
        end
        for i, entry in ipairs(filtered) do
          highlights[i] = entry
        end
      end
    end
    local border_group = nil
    local is_players_turn = match.current_state == match.STATE.PLAYER_TURN
      and match.current_player_index == user_entry.index
      and not player.folded
      and player.is_human
    if is_players_turn then
      border_group = PLAYER_ACTIVE_BORDER_GROUP
    elseif player_won then
      border_group = PLAYER_WIN_BORDER_GROUP
    elseif player.folded then
      border_group = PLAYER_FOLD_BORDER_GROUP
    end
    if border_group then
      add_border_highlights(lines, highlights, card_start, card_end, border_group, left_width)
    end
  end

  local function assign_players(players)
    local opponents = {}
    local user_entry = nil
    for index, player in ipairs(players or {}) do
      if player.is_human and not user_entry then
        user_entry = { player = player, index = index }
      else
        opponents[#opponents + 1] = { player = player, index = index }
      end
    end
    if not user_entry and players and players[1] then
      user_entry = { player = players[1], index = 1 }
      local filtered = {}
      for _, entry in ipairs(opponents) do
        if entry.index ~= 1 then
          filtered[#filtered + 1] = entry
        end
      end
      opponents = filtered
    end
    return opponents, user_entry
  end

  local function compact_opponent_summary(entry, reveal_all)
    local player = entry.player
    local display_cards = clone_cards_for_display(player.hole_cards, reveal_all)
    local cards_text = format_cards(display_cards, reveal_all)
    local suffix = player_position_suffix(entry.index)
    local display_name = (player.name or "Opponent") .. suffix
    local stack_text = string.format("stack:%d", player.stack or 0)
    local status_label, status_amount = status_label_and_amount(player)
    local status = status_label or ""
    if status_amount then
      status = status .. " " .. status_amount
    end
    if player.all_in and status ~= "" then
      status = status .. "+AI"
    elseif player.all_in then
      status = "AI"
    end
    local show_turn = match.current_state ~= match.STATE.HAND_OVER
    local is_active = show_turn and match.current_player_index == entry.index and not player.folded
    if is_active then
      status = status ~= "" and (status .. "*") or "*"
    end
    local parts = { display_name, cards_text, stack_text }
    if status ~= "" then
      parts[#parts + 1] = status
    end
    return table.concat(parts, "  "), status
  end

  local function render_players_compact(lines, players, reveal_all, width, highlights, board, layout_config)
    layout_config = layout_config or {}
    local left_width = layout_config.left_width or width
    local feed = layout_config.event_feed
    local opponents, user_entry = assign_players(players)
    local function write(text)
      return append_left_with_event(lines, text or "", feed, left_width)
    end

    local last_opponent_line = #lines
    if #opponents > 0 then
      last_opponent_line = write("Opponents:")
      for _, entry in ipairs(opponents) do
        local summary, status = compact_opponent_summary(entry, reveal_all)
        local idx = write(summary)
        add_line_highlight(highlights, idx, summary, status)
        last_opponent_line = idx
      end
    end

    write("")
    write("Board: " .. compact_board_line(board, reveal_all))
    write(string.format("Pot: %d   Current bet: %d", match.pot, match.current_bet))
    write("")

    if user_entry then
      local player = user_entry.player
      local suffix = player_position_suffix(user_entry.index)
      local header = (player.name or "Player") .. suffix
      local best_hand_text = player_best_hand_summary(player, board)
      if best_hand_text and best_hand_text ~= "" then
        header = string.format("%s - %s", header, best_hand_text)
      end
      write(header)
      local cards_line = "Cards: " .. format_cards(player_visible_cards(player.hole_cards), true)
      write(cards_line)
      local status_label, status_amount = status_label_and_amount(player)
      local stack_text = string.format("Stack: %d", player.stack or 0)
      if status_label and status_label ~= "" then
        if status_amount then
          stack_text = string.format("%s   %s %s", stack_text, status_label, status_amount)
        else
          stack_text = string.format("%s   %s", stack_text, status_label)
        end
      end
      local idx = write(stack_text)
      add_line_highlight(highlights, idx, stack_text, status_label)
      local contribution = pot_contribution_amount(player)
      if contribution then
        write(string.format("Contribution: %s", contribution))
      end
      if layout_config.action_text and layout_config.action_text ~= "" then
        local wrapped = wrap_action_text(layout_config.action_text, left_width)
        for _, action in ipairs(wrapped) do
          write(action)
        end
      end
    end

    return {
      last_opponent_line = last_opponent_line,
    }
  end

  local function render_players(lines, players, reveal_all, width, highlights, board, layout_config)
    layout_config = layout_config or {}
    if layout_config.compact then
      return render_players_compact(lines, players, reveal_all, width, highlights, board, layout_config)
    end
    local opponents, user_entry = assign_players(players)
    append_opponent_cards(lines, opponents, reveal_all, width, highlights)
    local last_opponent_line = #lines
    local left_width = layout_config.left_width or width
    local feed = layout_config.event_feed
    append_left_with_event(lines, "", feed, left_width)
    local board_layout = layout_config.board_layout or board_layout_for_width(left_width)
    layout_config.board_layout = board_layout
    local board_rows = build_board_rows(board, left_width, board_layout)
    for _, row in ipairs(board_rows) do
      append_left_with_event(lines, row, feed, left_width)
    end
    append_left_with_event(
      lines,
      center_text(string.format("Pot: %d   Current bet: %d", match.pot, match.current_bet), left_width),
      feed,
      left_width
    )
    if user_entry then
      append_left_with_event(lines, "", feed, left_width)
      local desired_inner = layout_config.player_panel_width or (left_width - 2)
      local inner_width = math.max(0, math.min(desired_inner, left_width - 2))
      local user_amount = pot_contribution_amount(user_entry.player)
      local amount_text = center_full(user_amount or "", inner_width)
      append_left_with_event(lines, center_text(amount_text, left_width), feed, left_width)
      render_user_row(lines, user_entry, width, highlights, board, layout_config)
    end
    return {
      last_opponent_line = last_opponent_line,
    }
  end

  local function action_line()
    if match.awaiting_restart then
      local primary = string.format("<%s> Play again", utils.keybindings.primary or "?")
      local quit = string.format("<%s> quit", utils.keybindings.quit or "?")
      return table.concat({ primary, quit }, "   ")
    end
    local primary_label = "waiting"
    local secondary_label = ""
    local bet_label = nil
    if match.current_state == match.STATE.PLAYER_TURN then
      local player = match.players[match.current_player_index]
      if player then
        local actions = match.available_actions(player)
        local state = match.get_state(player)
        local to_call = state and state.to_call or 0
        if vim.tbl_contains(actions, "call") and to_call > 0 then
          primary_label = string.format("call %d", to_call)
        elseif vim.tbl_contains(actions, "check") then
          primary_label = "check"
        elseif actions[1] then
          primary_label = actions[1]
        end
        if vim.tbl_contains(actions, "fold") then
          secondary_label = "fold"
        end
        if vim.tbl_contains(actions, "bet") then
          local min_bet = state and state.min_raise or 0
          bet_label = string.format("bet %d+", min_bet)
        elseif vim.tbl_contains(actions, "raise") then
          local min_raise = (state and state.current_bet or 0) + (state and state.min_raise or 0)
          bet_label = string.format("raise %d+", min_raise)
        end
      end
    elseif match.current_state == match.STATE.SHOWDOWN then
      primary_label = "showdown"
    elseif match.current_state == match.STATE.HAND_OVER then
      primary_label = "next hand"
    elseif match.current_state == match.STATE.AI_TURN then
      primary_label = "skip to turn"
    elseif match.current_state == match.STATE.DEALING then
      primary_label = "dealing"
    end
    local parts = {
      string.format("<%s> %s", utils.keybindings.primary or "?", primary_label),
    }
    if secondary_label ~= "" then
      parts[#parts + 1] = string.format("<%s> %s", utils.keybindings.secondary or "?", secondary_label)
    end
    if bet_label and utils.keybindings.bet then
      parts[#parts + 1] = string.format("<%s> %s", utils.keybindings.bet, bet_label)
    end
    parts[#parts + 1] = string.format("<%s> quit", utils.keybindings.quit or "?")
    return table.concat(parts, "   ")
  end

  split_action_tokens = function(text)
    local tokens = {}
    local start = 1
    while start <= #text do
      local sep_start = text:find("   ", start, true)
      if not sep_start then
        tokens[#tokens + 1] = vim.trim(text:sub(start))
        break
      end
      tokens[#tokens + 1] = vim.trim(text:sub(start, sep_start - 1))
      start = sep_start + 3
      while start <= #text and text:sub(start, start) == " " do
        start = start + 1
      end
    end
    return tokens
  end

  wrap_action_text = function(text, max_width)
    max_width = math.max(max_width or 0, 0)
    if text == nil or text == "" or max_width <= 0 then
      return {}
    end
    local tokens = split_action_tokens(text)
    local lines = {}
    local current = ""
    for _, token in ipairs(tokens) do
      if token ~= "" then
        if current == "" then
          current = token
        else
          local candidate = current .. "   " .. token
          if fn.strdisplaywidth(candidate) <= max_width then
            current = candidate
          else
            lines[#lines + 1] = current
            current = token
          end
        end
      end
    end
    if current ~= "" then
      lines[#lines + 1] = current
    end
    return lines
  end

  return {
    ensure_status_highlight_groups = ensure_status_highlight_groups,
    add_card_highlights = add_card_highlights,
    apply_status_highlights = apply_status_highlights,
    add_border_highlights = add_border_highlights,
    remove_highlights_in_range = remove_highlights_in_range,
    render_players = render_players,
    action_line = action_line,
    split_action_tokens = split_action_tokens,
    wrap_action_text = wrap_action_text,
  }
end

return M
