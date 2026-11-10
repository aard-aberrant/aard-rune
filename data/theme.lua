-- The theme: your changes to the colors. /theme lists every name you can
-- set here, in its colors, with what it's made of and where it shows;
-- anything not set keeps its default (core/theme.lua). Change, then /reload.
--
-- Two kinds of name:
--   palette  theme.yellow, theme.gray, theme.green_tc ... - change one and
--            every role built on it follows
--   roles    theme.caution, theme.quest.ready, theme.map.me ... - change
--            one and only it does
-- A value is any theme name - palette, role or group: theme.yellow,
-- theme.caution, theme.map.me - as changed here, or a color from
-- core/colors.lua (colors.amber_tc). bg(x) is x's background; mix(...) puts
-- several together. For example:
--   theme.yellow           = colors.amber_tc               -- every yellow role
--   theme.caution          = theme.orange_tc               -- only caution
--   theme.bcc.hot1         = theme.caution                 -- follows caution
--   theme.group.title_band = bg(theme.black_tc)
-- A palette name can be only a core/colors.lua color. A loop (a = theme.b,
-- b = theme.a) is warned about.
local theme = ...
local colors = require("core.colors")
local bg, mix = colors.bg, colors.mix

theme.group.title = mix(theme.underline, theme.yellow)   -- the group name, underlined
theme.reward.tab  = theme.dark                           -- the triangle
theme.reward.bg   = bg(theme.dark)                       -- the tab
