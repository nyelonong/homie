local notify = require("notify")

local home = os.getenv("HOME")
local np = home .. "/.local/bin/np"
local browser_cli = home .. "/.local/bin/terminal-browser"

local function message(text)
  notify("NordPass", text)
end

local function last_line(r)
  local out = (r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", "")
  return out:match("[^\n]*$")
end

local function host_of(url)
  local host = (url or ""):lower():gsub("^%a[%w+.-]*://", ""):match("^[^/?#]*") or ""
  return (host:gsub("^.*@", ""):gsub(":%d+$", ""):gsub("^www%.", ""))
end

local function same_site(a, b)
  if a == "" or b == "" then return false end
  return a == b or a:sub(-#b - 1) == "." .. b or b:sub(-#a - 1) == "." .. a
end

local function find_browser(block_id)
  local r = rex.exec({ browser_cli, "ls", "--all", "--json" }, { timeout = 10 })
  if not r or not r.ok then return nil, "terminal-browser is not responding" end
  local browsers = (rex.json.decode(r.stdout) or {}).browsers or {}
  if #browsers == 0 then return nil, "no terminal-browser is open" end
  local chosen = #browsers == 1 and browsers[1] or nil
  for _, b in ipairs(browsers) do
    if (b.pane or {}).pane == block_id then chosen = b end
  end
  if not chosen then return nil, "focus the terminal-browser pane first" end
  for _, tab in ipairs(chosen.tabs or {}) do
    if tab.active then return chosen, tab end
  end
  return nil, "the browser has no active tab"
end

-- Marks the login fields with data attributes so fill can target them by CSS.
-- Handles a password form and a username-only first step.
local mark_fields = [[(() => {
  const usable = e => e.offsetParent !== null && !e.disabled && !e.readOnly;
  const isUser = e => e.autocomplete === 'username' || ['text', 'email', 'tel', ''].includes((e.getAttribute('type') || '').toLowerCase());
  document.querySelectorAll('[data-np-user],[data-np-pass]').forEach(e => { e.removeAttribute('data-np-user'); e.removeAttribute('data-np-pass'); });
  const inputs = [...document.querySelectorAll('input')].filter(usable);
  const pass = inputs.find(e => e.type === 'password');
  const before = pass ? inputs.slice(0, inputs.indexOf(pass)).reverse() : inputs;
  const user = before.find(isUser);
  if (pass) pass.setAttribute('data-np-pass', '');
  if (user) user.setAttribute('data-np-user', '');
  return (user ? 'user' : '') + (pass ? 'pass' : '');
})()]]

local function act(browser, tab, ...)
  local argv = { browser_cli, "action", "--browser", browser.key, "--tab", tostring(tab.id), "--" }
  for _, a in ipairs({ ... }) do argv[#argv + 1] = a end
  local r, err = rex.exec(argv, { timeout = 20 })
  return r or { ok = false, stdout = "", stderr = err }
end

local function choose(items, site)
  local matches, rest = {}, {}
  for _, item in ipairs(items) do
    local entry = {
      id = item.id,
      title = item.title or item.id,
      subtitle = item.username,
      detail = host_of(item.url),
      icon = "person",
    }
    if same_site(host_of(item.url), site) then
      matches[#matches + 1] = entry
    else
      rest[#rest + 1] = entry
    end
  end

  -- rex.ui needs a server with control API revision 17 or later.
  if not (rex.ui and rex.ui.pick) then
    if #matches == 1 then return matches[1].id end
    return nil, string.format("%d logins match %s; restart the Rex server to get the picker", #matches, site)
  end

  local list = {}
  for _, e in ipairs(matches) do list[#list + 1] = e end
  for _, e in ipairs(rest) do list[#list + 1] = e end
  local id = rex.ui.pick{
    title = "Fill password",
    placeholder = #matches > 0 and ("Logins for " .. site) or "Search NordPass logins",
    items = list,
  }
  return id
end

rex.action{
  name = "nordpass_fill",
  title = "NordPass: Fill Password…",
  category = "NordPass",
  keywords = "password login nordpass fill browser",
  run = function(ctx)
    local browser, tab = find_browser(ctx.block_id)
    if not browser then return message(tab) end
    local site = host_of(tab.url)

    local r = rex.exec({ np, "item", "list", "--type", "password", "--format", "json" }, { timeout = 30 })
    if not r or not r.ok then
      return message("Could not list logins (" .. (r and last_line(r) or "np missing") .. "). Run np unlock in a pane.")
    end
    local id, why = choose(rex.json.decode(r.stdout) or {}, site)
    if not id then
      if why then message(why) end
      return
    end

    local marked = act(browser, tab, "eval", mark_fields)
    if not marked or not marked.ok then return message("Could not read the page: " .. last_line(marked)) end
    local fields = marked.stdout
    if not fields:find("user") and not fields:find("pass") then
      return message("No login field on " .. (site ~= "" and site or "this page"))
    end

    local item = rex.exec({ np, "item", "get", id, "--format", "json" }, { timeout = 30 })
    if not item or not item.ok then return message("Could not read the login: " .. last_line(item)) end
    local login = rex.json.decode(item.stdout) or {}

    -- agent-browser fill takes the value as an argument; it is visible in the
    -- process list only while that command runs.
    if fields:find("user") and (login.username or "") ~= "" then
      local f = act(browser, tab, "fill", "[data-np-user]", login.username)
      if not f.ok then return message("Could not fill the username: " .. last_line(f)) end
    end
    if fields:find("pass") and (login.password or "") ~= "" then
      local f = act(browser, tab, "fill", "[data-np-pass]", login.password)
      if not f.ok then return message("Could not fill the password: " .. last_line(f)) end
    end
  end,
}
