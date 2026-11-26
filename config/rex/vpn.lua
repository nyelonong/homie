local netbird = "/usr/local/bin/netbird"
local tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
local notify = require("notify")

local function json(argv)
  local r = rex.exec(argv, { timeout = 10 })
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

local function toggle(vpn)
  local up = vpn.status()
  local r, err = rex.exec(up and vpn.down or vpn.up, { timeout = 60 })
  if not r then
    notify("VPN", vpn.title .. " failed: " .. err)
  elseif not r.ok then
    local out = (r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", "")
    local why = out:match("[^\n]*$")
    notify("VPN", vpn.title .. " failed: " .. why)
  else
    local now = vpn.status()
    notify("VPN", vpn.title .. (now and " connected" or " disconnected"))
  end
end

for _, vpn in ipairs(vpns) do
  rex.action{
    name = "vpn_" .. vpn.id,
    title = "VPN: Connect or Disconnect " .. vpn.title,
    category = "VPN",
    keywords = "vpn network",
    run = function() toggle(vpn) end,
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
        if vpn.id == choice then toggle(vpn) end
      end
    end
  end,
}
