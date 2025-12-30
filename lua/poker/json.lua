-- Minimal JSON helper with fallbacks so tests do not depend on external modules.
-- Prefers cjson/dkjson when available, otherwise uses a small encoder/decoder.
local ok, cjson = pcall(require, "cjson")
if ok then
  return cjson
end

local ok_dk, dkjson = pcall(require, "dkjson")
if ok_dk then
  return dkjson
end

local json = {}

local function escape(str)
  return (str:gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t"))
end

local function encode_value(val)
  local t = type(val)
  if t == "table" then
    local is_array = (#val > 0)
    local parts = {}
    if is_array then
      for i = 1, #val do
        parts[#parts + 1] = encode_value(val[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(val) do
        parts[#parts + 1] = string.format("\"%s\":%s", tostring(k), encode_value(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  elseif t == "string" then
    return "\"" .. escape(val) .. "\""
  elseif t == "number" or t == "boolean" then
    return tostring(val)
  elseif val == nil then
    return "null"
  else
    error("cannot encode type " .. t)
  end
end

function json.encode(tbl)
  return encode_value(tbl)
end

local function decode_error(message, index)
  error(string.format("json decode failed at %d: %s", index, message))
end

local function skip_ws(str, index)
  local length = #str
  while index <= length do
    local c = str:sub(index, index)
    if c ~= " " and c ~= "\n" and c ~= "\t" and c ~= "\r" then
      break
    end
    index = index + 1
  end
  return index
end

local function utf8_from_codepoint(code)
  if code <= 0x7F then
    return string.char(code)
  elseif code <= 0x7FF then
    return string.char(
      0xC0 + math.floor(code / 0x40),
      0x80 + (code % 0x40)
    )
  elseif code <= 0xFFFF then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + (math.floor(code / 0x40) % 0x40),
      0x80 + (code % 0x40)
    )
  elseif code <= 0x10FFFF then
    return string.char(
      0xF0 + math.floor(code / 0x40000),
      0x80 + (math.floor(code / 0x1000) % 0x40),
      0x80 + (math.floor(code / 0x40) % 0x40),
      0x80 + (code % 0x40)
    )
  end
  decode_error("invalid unicode codepoint", 1)
end

local function read_hex(str, index)
  local hex = str:sub(index, index + 3)
  if #hex < 4 or not hex:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
    decode_error("invalid unicode escape", index)
  end
  return tonumber(hex, 16)
end

local parse_value

local function parse_string(str, index)
  index = index + 1
  local out = {}
  while true do
    local c = str:sub(index, index)
    if c == "" then
      decode_error("unterminated string", index)
    end
    if c == "\"" then
      return table.concat(out), index + 1
    end
    if c == "\\" then
      local esc = str:sub(index + 1, index + 1)
      if esc == "" then
        decode_error("unterminated escape", index)
      end
      if esc == "\"" or esc == "\\" or esc == "/" then
        out[#out + 1] = esc
        index = index + 2
      elseif esc == "b" then
        out[#out + 1] = "\b"
        index = index + 2
      elseif esc == "f" then
        out[#out + 1] = "\f"
        index = index + 2
      elseif esc == "n" then
        out[#out + 1] = "\n"
        index = index + 2
      elseif esc == "r" then
        out[#out + 1] = "\r"
        index = index + 2
      elseif esc == "t" then
        out[#out + 1] = "\t"
        index = index + 2
      elseif esc == "u" then
        local code = read_hex(str, index + 2)
        index = index + 6
        if code >= 0xD800 and code <= 0xDBFF then
          if str:sub(index, index + 1) ~= "\\u" then
            decode_error("missing low surrogate", index)
          end
          local low = read_hex(str, index + 2)
          if low < 0xDC00 or low > 0xDFFF then
            decode_error("invalid low surrogate", index)
          end
          code = 0x10000 + ((code - 0xD800) * 0x400) + (low - 0xDC00)
          index = index + 6
        elseif code >= 0xDC00 and code <= 0xDFFF then
          decode_error("unexpected low surrogate", index)
        end
        out[#out + 1] = utf8_from_codepoint(code)
      else
        decode_error("invalid escape", index)
      end
    else
      out[#out + 1] = c
      index = index + 1
    end
  end
end

local function parse_number(str, index)
  local start = index
  local c = str:sub(index, index)
  if c == "-" then
    index = index + 1
  end
  c = str:sub(index, index)
  if c == "" or not c:match("%d") then
    decode_error("invalid number", index)
  end
  if c == "0" then
    index = index + 1
  else
    while str:sub(index, index):match("%d") do
      index = index + 1
    end
  end
  if str:sub(index, index) == "." then
    index = index + 1
    if not str:sub(index, index):match("%d") then
      decode_error("invalid number", index)
    end
    while str:sub(index, index):match("%d") do
      index = index + 1
    end
  end
  local exp = str:sub(index, index)
  if exp == "e" or exp == "E" then
    index = index + 1
    local sign = str:sub(index, index)
    if sign == "+" or sign == "-" then
      index = index + 1
    end
    if not str:sub(index, index):match("%d") then
      decode_error("invalid number", index)
    end
    while str:sub(index, index):match("%d") do
      index = index + 1
    end
  end
  local number_str = str:sub(start, index - 1)
  return tonumber(number_str), index
end

local function parse_array(str, index)
  index = index + 1
  local arr = {}
  index = skip_ws(str, index)
  if str:sub(index, index) == "]" then
    return arr, index + 1
  end
  while true do
    local value
    value, index = parse_value(str, index)
    arr[#arr + 1] = value
    index = skip_ws(str, index)
    local c = str:sub(index, index)
    if c == "," then
      index = skip_ws(str, index + 1)
    elseif c == "]" then
      return arr, index + 1
    else
      decode_error("expected ',' or ']'", index)
    end
  end
end

local function parse_object(str, index)
  index = index + 1
  local obj = {}
  index = skip_ws(str, index)
  if str:sub(index, index) == "}" then
    return obj, index + 1
  end
  while true do
    if str:sub(index, index) ~= "\"" then
      decode_error("expected string key", index)
    end
    local key
    key, index = parse_string(str, index)
    index = skip_ws(str, index)
    if str:sub(index, index) ~= ":" then
      decode_error("expected ':'", index)
    end
    index = skip_ws(str, index + 1)
    local value
    value, index = parse_value(str, index)
    obj[key] = value
    index = skip_ws(str, index)
    local c = str:sub(index, index)
    if c == "," then
      index = skip_ws(str, index + 1)
    elseif c == "}" then
      return obj, index + 1
    else
      decode_error("expected ',' or '}'", index)
    end
  end
end

parse_value = function(str, index)
  index = skip_ws(str, index)
  local c = str:sub(index, index)
  if c == "\"" then
    return parse_string(str, index)
  elseif c == "{" then
    return parse_object(str, index)
  elseif c == "[" then
    return parse_array(str, index)
  elseif c == "-" or c:match("%d") then
    return parse_number(str, index)
  elseif str:sub(index, index + 3) == "true" then
    return true, index + 4
  elseif str:sub(index, index + 4) == "false" then
    return false, index + 5
  elseif str:sub(index, index + 3) == "null" then
    return nil, index + 4
  end
  decode_error("unexpected character", index)
end

local function safe_decode(str)
  local value, index = parse_value(str, 1)
  index = skip_ws(str, index)
  if index <= #str then
    decode_error("trailing characters", index)
  end
  return value
end

function json.decode(str)
  if vim and vim.json and type(vim.json.decode) == "function" and vim.json.decode ~= json.decode then
    return vim.json.decode(str)
  end
  if vim and vim.fn and type(vim.fn.json_decode) == "function" and vim.fn.json_decode ~= json.decode then
    return vim.fn.json_decode(str)
  end
  return safe_decode(str)
end

return json
