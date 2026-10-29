-- boot-test-bindings.lua: print the keybindings a Hyprland Lua configuration makes, for
-- rootfs-boot-test.sh's desktop checks.
--
-- Anatomy: Lua (lua5.4, installed in the guest by the boot test) runs the user's
-- ~/.config/hypr/hyprland.lua, which loads the distro's defaults from /usr/share/<id>/default/hypr
-- as Hyprland does. A stand-in for Hyprland's "hl" table records each hl.bind call instead of
-- binding a key; hl.dsp.exec_cmd returns the command line it was given, so a binding that runs a
-- command can be told from one that runs a built-in dispatcher (moving a window, say). Every
-- other hl call does nothing. The output is one tab-separated line per binding:
--   <keys> <description> <command, or empty for a built-in dispatcher>
-- santisbon/omarchy's test/shell.d/hyprland-binding-commands-test.sh uses the same stand-in on the
-- un-renamed tree.
--
-- Usage: HOME=<home> OMARCHY_PATH=/usr/share/<id> lua5.4 boot-test-bindings.lua <hyprland.lua>
local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function() return {} end,
  })
end

local dsp = proxy()
rawset(dsp, "exec_cmd", function(command) return { command = command } end)

local bindings = {}
hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    local command = type(dispatcher) == "table" and dispatcher.command or ""
    table.insert(bindings, { keys = keys, description = opts.description or "", command = command })
  end,
  get_config = function() return nil end,
  get_active_window = function() return nil end,
}, {
  __index = function() return function() return {} end end,
})

dofile(arg[1])

for _, b in ipairs(bindings) do
  print(b.keys .. "\t" .. b.description .. "\t" .. b.command)
end
