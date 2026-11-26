local shell = os.getenv("SHELL") or "/bin/zsh"

local function folder_of_focused_pane()
  local p = rex.block.call("com.superlogical.terminal", "process") or {}
  return (p.foreground or {}).cwd or (p.child or {}).cwd or os.getenv("HOME")
end

rex.action{
  name = "yazi",
  title = "Files: Open Yazi Here",
  category = "Files",
  keywords = "file manager browse finder yazi",
  run = function(ctx)
    local _, err = rex.call("session.new_split", {
      session_id = ctx.session_id,
      anchor_id = ctx.block_id,
      direction = "horizontal",
      side = "after",
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = {
          -- An interactive login shell gives yazi the full PATH for openers and editors.
          command = { shell, "-lic", "exec yazi" },
          shell = "none",
          cwd = folder_of_focused_pane(),
        },
      },
    })
    if err then rex.log("warn", "yazi: " .. tostring(err)) end
  end,
}

rex.bind("cmd+e", "yazi")
