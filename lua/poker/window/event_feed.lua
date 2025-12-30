local M = {}

function M.setup(ctx)
  local match = ctx.match
  local utils = ctx.utils
  local fn = ctx.fn
  local pad_to_width = ctx.pad_to_width
  local current_window_width = ctx.current_window_width
  local event_feed_height = ctx.event_feed_height
  local event_sep_left = ctx.event_sep_left

  local function append_left_with_event(lines, left_text, event_feed, left_width)
    left_width = math.max(left_width or current_window_width(), 0)
    lines[#lines + 1] = pad_to_width(left_text or "", left_width)
    return #lines
  end

  local function append_remaining_events()
    -- Events are merged after layout; nothing to do here.
  end

  local function build_event_lines(width, desired_height)
    if not width or width <= 0 then
      return {}
    end
    local height = desired_height or event_feed_height
    if height < 6 then
      height = 6
    end
    local inner_width = math.max(width - 2, 0)
    local content_capacity = math.max(height - 6, 0) -- header + divider + hint divider + hint + bottom
    local stats_key = utils.keybindings.stats or ";"
    local stats_hint = string.format("Press %s for stats", stats_key)
    local lines = {}
    lines[#lines + 1] = "╭" .. string.rep("─", inner_width) .. "╮"
    lines[#lines + 1] = "│" .. pad_to_width("Recent Events", inner_width) .. "│"
    lines[#lines + 1] = "├" .. string.rep("─", inner_width) .. "┤"
    local added = 0
    if match.last_events and not vim.tbl_isempty(match.last_events) then
      local start_idx = math.max(#match.last_events - content_capacity + 1, 1)
      for idx = #match.last_events, start_idx, -1 do
        lines[#lines + 1] = "│" .. pad_to_width(match.last_events[idx], inner_width) .. "│"
        added = added + 1
      end
    else
      lines[#lines + 1] = "│" .. pad_to_width("--", inner_width) .. "│"
      added = added + 1
    end
    while added < content_capacity do
      lines[#lines + 1] = "│" .. pad_to_width("", inner_width) .. "│"
      added = added + 1
    end
    lines[#lines + 1] = "├" .. string.rep("─", inner_width) .. "┤"
    lines[#lines + 1] = "│" .. pad_to_width(stats_hint, inner_width) .. "│"
    lines[#lines + 1] = "╰" .. string.rep("─", inner_width) .. "╯"
    return lines
  end

  local function merge_with_events(left_lines, event_feed, left_width, min_start_line)
    if not event_feed or not event_feed.width or event_feed.width <= 0 then
      return left_lines
    end
    local right_lines = event_feed.lines or {}
    local left_len = #left_lines
    local right_len = #right_lines
    local base_start = left_len - right_len + 1
    local start_line = min_start_line or base_start
    if start_line < 1 then
      start_line = 1
    end
    local total_lines = math.max(left_len, start_line + right_len - 1)
    while #left_lines < total_lines do
      left_lines[#left_lines + 1] = ""
    end
    while #left_lines < total_lines do
      left_lines[#left_lines + 1] = ""
    end
    local merged = {}
    for i = 1, total_lines do
      local left_text = pad_to_width(left_lines[i] or "", left_width)
      local right_idx = i - start_line + 1
      local right_text = ""
      if right_idx >= 1 and right_idx <= right_len then
        right_text = right_lines[right_idx] or ""
      end
      right_text = pad_to_width(right_text, event_feed.width)
      merged[i] = left_text .. event_sep_left .. right_text
    end
    return merged
  end

  return {
    append_left_with_event = append_left_with_event,
    append_remaining_events = append_remaining_events,
    build_event_lines = build_event_lines,
    merge_with_events = merge_with_events,
  }
end

return M
