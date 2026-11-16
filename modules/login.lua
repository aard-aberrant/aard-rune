-- Logging in (tt++ conf/credentials.tin + modules/gmcp.tin's SESSION
-- CONNECTED): answers the game's two login prompts from .env in the config
-- directory - make it from .env.example, and keep it chmod 600:
--   NAME=yourname
--   PASSWORD=yourpassword      (leave it out to type it yourself)
-- As other .env readers: spaces around a value are dropped, and so is a
-- " # comment" after it. A value in matching quotes ("..." or '...') is
-- kept exactly as written inside them - quote a password that has spaces
-- at its ends or " #" in it. # starts a comment line. No .env or no NAME:
-- the prompts are left for you.
-- Game text (there is no GMCP before you're in), the prompts as seen live
-- 2026-11-06:
--   What be thy name, adventurer?
--   Existing profile loaded - please enter your password.
-- Each is answered once per connection. Rune hands a line to a trigger as
-- output or as a prompt (a partial line, on: "prompt"), and which these are
-- isn't known, so both are watched - only until you're in the game.
-- send_raw: no alias or ; expansion.
-- Once in the game (a real login, not a /reload), heighten senses - below.

local game = require("modules.game")   -- on_login: in the game

local env = {}
local f = io.open(rune.config_dir .. "/.env", "r")
if f then
  for raw in f:lines() do
    local line = raw:gsub("\r$", "")
    local key, value = line:match("^%s*([%w_]+)%s*=(.*)$")
    if key and not line:match("^%s*#") then
      value = value:match("^%s*(.-)%s*$")
      local q = value:sub(1, 1)
      local close = (q == '"' or q == "'") and value:find(q, 2, true)
      if close then
        value = value:sub(2, close - 1)          -- quoted: as written
      else
        value = value:gsub("%s+#.*$", "")        -- unquoted: no comment
      end
      env[key] = value
    end
  end
  f:close()
end
local name = env.NAME
local cred = name and name ~= "" and { name = name, password = env.PASSWORD ~= "" and env.PASSWORD or nil } or nil

if cred and cred.name then
  local name_sent, pw_sent = false, false
  local trigs = {}

  -- The four prompt triggers exist only from connecting to being in the
  -- game: added at load and on each connect, removed at login
  local function disarm()
    for _, t in ipairs(trigs) do t:remove() end
    trigs = {}
  end
  local function name()
    if name_sent then return end
    name_sent = true
    rune.send_raw(cred.name)
  end
  local function password()
    if pw_sent or not cred.password then return end
    pw_sent = true
    rune.send_raw(cred.password)
  end
  local function arm()
    disarm()
    name_sent, pw_sent = false, false
    for _, on in ipairs({ "output", "prompt" }) do
      trigs[#trigs + 1] = rune.trigger.contains("What be thy name, adventurer?", name, { name = "login_name_" .. on, on = on })
      trigs[#trigs + 1] = rune.trigger.contains("please enter your password", password, { name = "login_pw_" .. on, on = on })
    end
  end
  arm()
  rune.hooks.on("connecting", arm, { name = "login_reset" })
  game.on_login(disarm)   -- in the game, so the watch goes
end

-- Heighten senses at each real login - Rune started, or a reconnect - with
-- or without .env; not after a /reload (the user, 2026-11-13). With it off,
-- a dark room (home) shows nothing - "You see nothing but darkness...",
-- DARKNESS in the minimap. Sent even when it's up: the reply, "Your senses
-- are already heightened." (the user, 2026-11-13), shows, as the casting
-- lines do. Registered here, before modules/minimap.lua loads, so it is sent
-- before the minimap's login "map" - the game answers in order, so that map
-- is drawn after you can see. Not while fighting (state 8).
-- game.on_login fires after a /reload too; rune.session (kept across a
-- /reload, not a restart) tells them apart: "1" from login to disconnect
local IN_GAME = "login_in_game"
local reloaded = rune.session.get(IN_GAME) == "1"   -- in the game before this /reload
game.on_login(function()
  local skip = reloaded
  reloaded = false
  rune.session.set(IN_GAME, "1")
  if not skip and game.state ~= 8 then rune.send_raw("heighten") end
end)
rune.hooks.on("disconnected", function() rune.session.set(IN_GAME, "0") end, { name = "login_left_game" })
