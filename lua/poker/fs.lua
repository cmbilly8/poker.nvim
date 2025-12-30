local M = {}

local function dirname(path)
  if not path then
    return nil
  end
  local normalized = path:gsub("\\", "/")
  local dir = normalized:match("^(.*)/[^/]+$")
  if dir == nil or dir == "" then
    return nil
  end
  if path:find("\\", 1, true) and not path:find("/", 1, true) then
    dir = dir:gsub("/", "\\")
  end
  return dir
end

local function ensure_dir_with_lfs(dir)
  local ok_lfs, lfs = pcall(require, "lfs")
  if not ok_lfs or not lfs or type(lfs.mkdir) ~= "function" then
    return false
  end
  local sep = package.config:sub(1, 1)
  local prefix = ""
  local path = dir
  if sep == "\\" then
    local drive = dir:match("^(%a:)[/\\]")
    if drive then
      prefix = drive .. sep
      path = dir:sub(#drive + 2)
    elseif dir:sub(1, 1) == sep then
      prefix = sep
      path = dir:sub(2)
    end
  elseif dir:sub(1, 1) == sep then
    prefix = sep
    path = dir:sub(2)
  end
  local current = prefix
  for part in string.gmatch(path, "[^" .. sep .. "]+") do
    if current == "" or current == prefix then
      current = current .. part
    else
      current = current .. sep .. part
    end
    lfs.mkdir(current)
  end
  return true
end

function M.ensure_dir(dir)
  if not dir or dir == "" then
    return false
  end
  if vim and vim.fn and type(vim.fn.mkdir) == "function" then
    vim.fn.mkdir(dir, "p")
    return true
  end
  local ok_path, path_mod = pcall(require, "plenary.path")
  if ok_path and path_mod and path_mod.new then
    local p = path_mod.new(dir)
    if p and p.mkdir then
      p:mkdir({ parents = true })
      return true
    end
  end
  return ensure_dir_with_lfs(dir)
end

function M.ensure_parent_dir(path)
  local dir = dirname(path)
  if not dir then
    return false
  end
  return M.ensure_dir(dir)
end

function M.open(path, mode)
  return io.open(path, mode)
end

function M.read_file(path)
  local f = M.open(path, "r")
  if not f then
    return nil
  end
  local contents = f:read("*a")
  f:close()
  return contents
end

function M.write_file(path, contents, mode)
  M.ensure_parent_dir(path)
  local f = M.open(path, mode or "w")
  if not f then
    return false
  end
  if contents ~= nil then
    f:write(contents)
  end
  f:close()
  return true
end

function M.append_file(path, contents)
  return M.write_file(path, contents, "a")
end

function M.file_exists(path)
  local f = M.open(path, "r")
  if not f then
    return false
  end
  f:close()
  return true
end

function M.atomic_write(path, contents)
  M.ensure_parent_dir(path)
  local tmp_path = path .. ".tmp"
  local f = M.open(tmp_path, "w")
  if not f then
    return M.write_file(path, contents, "w")
  end
  if contents ~= nil then
    f:write(contents)
  end
  f:close()
  os.rename(tmp_path, path)
  return true
end

return M
