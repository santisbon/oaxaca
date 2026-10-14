-- Generated from packages/session/sddm-greeter-hyprland.lua.in by scripts/render.py. Edit the .in file, not this one.
-- Installed by oaxaca-session: the Hyprland configuration for SDDM's greeter.
-- SDDM starts this compositor as the sddm user, then starts the greeter inside it
-- (CompositorCommand in /etc/sddm.conf.d/10-oaxaca-wayland.conf). The greeter is the
-- only client, so Hyprland's logo, splash, wallpaper and animations are turned off.
-- Same settings as Omarchy's default/sddm/hyprland.lua (v4.0.4).
hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },
  animations = {
    enabled = false,
  },
})
