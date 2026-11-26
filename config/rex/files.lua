local notify = require("notify")

local shell = os.getenv("SHELL") or "/bin/zsh"
local terminal = "com.superlogical.terminal"
local tail_bytes = 256 * 1024

local function folder_of_focused_pane()
  local p = rex.block.call(terminal, "process") or {}
  return (p.foreground or {}).cwd or (p.child or {}).cwd or os.getenv("HOME")
end

local function open_yazi(ctx, cwd, entry)
  -- An interactive login shell gives yazi the full PATH for openers and editors.
  local command = { shell, "-lic", entry and 'exec yazi "$0"' or "exec yazi" }
  if entry then command[#command + 1] = entry end
  local _, err = rex.call("session.new_split", {
    session_id = ctx.session_id,
    anchor_id = ctx.block_id,
    direction = "horizontal",
    side = "after",
    focus = true,
    layout = rex.layout.block{
      flavor = terminal .. ".shell",
      options = { command = command, shell = "none", cwd = cwd },
    },
  })
  if err then rex.log("warn", "yazi: " .. tostring(err)) end
end

-- The end of the focused pane as HTML, where terminal hyperlinks become <a href>.
local function recent_html()
  local first = rex.block.call(terminal, "format", { format = "html", max_bytes = 64 })
  if not first then return "" end
  if not first.id then return first.content or "" end
  local parts, offset = {}, math.max(0, (first.total or 0) - tail_bytes)
  while true do
    local r = rex.block.call(terminal, "blob_read", { id = first.id, offset = offset, max_bytes = 983040 })
    if not r or not r.data or r.data == "" then break end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
    if r.eof then break end
  end
  return table.concat(parts)
end

local function last_file_link(html)
  local last
  for href in html:gmatch('href="file://([^"]+)"') do last = href end
  if not last then return nil end
  local path = last:gsub("&amp;", "&"):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return (path:gsub("^[^/]+", ""))
end

rex.action{
  name = "yazi",
  title = "Files: Open Yazi Here",
  category = "Files",
  keywords = "file manager browse finder yazi",
  run = function(ctx) open_yazi(ctx, folder_of_focused_pane()) end,
}

rex.action{
  name = "yazi_last_link",
  title = "Files: Open Last Link in Yazi",
  category = "Files",
  keywords = "file manager link path claude screenshot yazi",
  run = function(ctx)
    local path = last_file_link(recent_html())
    if not path then return notify("Files", "No file link in this pane") end
    if rex.exec({ "test", "-d", path }).ok then return open_yazi(ctx, path) end
    if not rex.exec({ "test", "-e", path }).ok then return notify("Files", "Not found: " .. path) end
    open_yazi(ctx, path:match("^(.*)/[^/]*$"), path)
  end,
}

rex.bind("cmd+e", "yazi")
rex.bind("shift+cmd+e", "yazi_last_link")
