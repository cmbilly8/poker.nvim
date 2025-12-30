local M = {}

function M.setup(ctx)
  local fn = ctx.fn
  local get_win_width = ctx.get_win_width
  local board_card_inner_width = ctx.board_card_inner_width
  local card_spacing = ctx.card_spacing
  local max_window_width = ctx.max_window_width
  local min_window_height = ctx.min_window_height
  local max_window_height = ctx.max_window_height
  local window_side_padding = ctx.window_side_padding
  local border_total = ctx.border_total

  local function min_content_width()
    return math.max((board_card_inner_width + 2) * 5 + (card_spacing * 4), 30)
  end

  local function preferred_width(columns)
    columns = math.max(columns or vim.o.columns or 1, 1)
    local usable = math.max(columns - border_total, 1)
    local target = math.max(min_content_width(), usable - window_side_padding)
    target = math.min(target, max_window_width)
    if target > usable then
      target = usable
    end
    return target
  end

  local function preferred_height(lines)
    lines = math.max(lines or vim.o.lines or 1, 1)
    local usable = math.max(lines - border_total, 1)
    local target = math.max(min_window_height, usable - window_side_padding)
    target = math.min(target, max_window_height)
    if target > usable then
      target = usable
    end
    return target
  end

  local function popup_dimensions(width_override, height_override)
    local width = width_override or preferred_width(vim.o.columns)
    local height = height_override or preferred_height(vim.o.lines)
    local max_columns = math.max(1, vim.o.columns)
    local max_lines = math.max(1, vim.o.lines)
    local total_width = width + border_total
    local total_height = height + border_total
    local row = math.max(0, math.floor((max_lines - total_height) / 2))
    local col = math.max(0, math.floor((max_columns - total_width) / 2))
    return width, height, row, col
  end

  local function board_layout_for_width(width)
    width = math.max(width or min_content_width(), 0)
    local inner_width = board_card_inner_width
    local spacing = card_spacing
    local function row_width()
      local card_width = inner_width + 2
      return card_width * 5 + spacing * 4
    end
    local guard = 0
    while width > 0 and row_width() > width and guard < 50 do
      if spacing > 0 then
        spacing = spacing - 1
      elseif inner_width > 1 then
        inner_width = inner_width - 1
      else
        break
      end
      guard = guard + 1
    end
    return {
      inner_width = inner_width,
      spacing = spacing,
      row_width = row_width(),
    }
  end

  local function current_window_width()
    local width = get_win_width and get_win_width()
    if width then
      return width
    end
    return preferred_width(vim.o.columns)
  end

  local function center_text(text, width)
    width = width or current_window_width()
    text = text or ""
    local text_width = fn.strdisplaywidth(text)
    if text_width >= width then
      return text
    end
    local padding = math.floor((width - text_width) / 2)
    if padding <= 0 then
      return text
    end
    return string.rep(" ", padding) .. text
  end

  local function center_full(text, width)
    width = width or current_window_width()
    text = text or ""
    local text_width = fn.strdisplaywidth(text)
    if text_width >= width then
      return text
    end
    local total = width - text_width
    local left = math.floor(total / 2)
    local right = total - left
    return string.rep(" ", left) .. text .. string.rep(" ", right)
  end

  local function pad_to_width(text, width)
    text = text or ""
    width = math.max(width or 0, 0)
    local display = fn.strdisplaywidth(text)
    if display >= width then
      return text
    end
    return text .. string.rep(" ", width - display)
  end

  return {
    min_content_width = min_content_width,
    preferred_width = preferred_width,
    preferred_height = preferred_height,
    popup_dimensions = popup_dimensions,
    board_layout_for_width = board_layout_for_width,
    current_window_width = current_window_width,
    center_text = center_text,
    center_full = center_full,
    pad_to_width = pad_to_width,
  }
end

return M
