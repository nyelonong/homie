local netbird = "/usr/local/bin/netbird"
local tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
local notify = require("notify")

local function json(argv)
  local r = rex.exec(argv, { timeout = 3 })
  if not r or not r.ok or r.stdout == "" then return {} end
  local ok, value = pcall(rex.json.decode, r.stdout)
  return ok and type(value) == "table" and value or {}
end

local vpns = {
  {
    id = "netbird",
    title = "NetBird",
    status = function()
      local s = json({ netbird, "status", "--json" })
      local peers = s.peers or {}
      return (s.management or {}).connected == true,
        string.format("%s  peers %d/%d", s.netbirdIp or "-", peers.connected or 0, peers.total or 0)
    end,
    up = { netbird, "up" },
    down = { netbird, "down" },
  },
  {
    id = "tailscale",
    title = "Tailscale",
    status = function()
      local s = json({ tailscale, "status", "--json" })
      local ips = (s.Self or {}).TailscaleIPs or {}
      return s.BackendState == "Running",
        string.format("%s  %s", ips[1] or "-", (s.CurrentTailnet or {}).Name or "")
    end,
    up = { tailscale, "up" },
    down = { tailscale, "down" },
  },
}

-- Palette titles are fixed when the config loads, so reloading it after a
-- change is what keeps "Connect" and "Disconnect" in step with the VPN.
local function refresh_titles()
  local ok, err = rex.call("server.config_reload")
  if not ok and err then rex.log("warn", "vpn: config reload failed: " .. tostring(err)) end
end

local function set_state(vpn, want_up)
  if vpn.status() == want_up then
    notify("VPN", vpn.title .. (want_up and " is already connected" or " is already disconnected"))
    return refresh_titles()
  end
  local r, err = rex.exec(want_up and vpn.up or vpn.down, { timeout = 60 })
  if not r then
    notify("VPN", vpn.title .. " failed: " .. err)
  elseif not r.ok then
    local out = (r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", "")
    notify("VPN", vpn.title .. " failed: " .. out:match("[^\n]*$"))
  else
    notify("VPN", vpn.title .. (vpn.status() and " connected" or " disconnected"))
  end
  refresh_titles()
end

for _, vpn in ipairs(vpns) do
  local up = vpn.status()
  rex.action{
    name = "vpn_" .. vpn.id,
    title = (up and "VPN: Disconnect " or "VPN: Connect ") .. vpn.title,
    category = "VPN",
    keywords = "vpn network connect disconnect",
    run = function() set_state(vpn, not up) end,
  }
end

rex.action{
  name = "vpn",
  title = "VPN…",
  category = "VPN",
  keywords = "vpn network netbird tailscale status",
  run = function()
    -- rex.ui needs a server with control API revision 17 or later.
    if not (rex.ui and rex.ui.pick) then
      local lines = {}
      for _, vpn in ipairs(vpns) do
        local up, detail = vpn.status()
        lines[#lines + 1] = vpn.title .. ": " .. (up and "connected " or "disconnected ") .. detail
      end
      notify("VPN", table.concat(lines, "\n"))
      return
    end
    while true do
      local items = {}
      for _, vpn in ipairs(vpns) do
        local up, detail = vpn.status()
        items[#items + 1] = {
          id = vpn.id,
          title = (up and "● " or "○ ") .. vpn.title,
          subtitle = detail,
          detail = up and "Disconnect" or "Connect",
          icon = "globe",
        }
      end
      local choice = rex.ui.pick{ title = "VPN", placeholder = "Choose a VPN to connect or disconnect", items = items }
      if choice == nil then return end
      for _, vpn in ipairs(vpns) do
        if vpn.id == choice then set_state(vpn, not vpn.status()) end
      end
    end
  end,
}
