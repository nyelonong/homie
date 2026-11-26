-- Rex has no toast API, so messages go to Notification Center.
return function(title, text)
  rex.exec({
    "osascript",
    "-e", "on run argv",
    "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
    "-e", "end run",
    title,
    text,
  })
end
