-- Edits one value in a hand-written Lua data file (require("lib.luaedit")),
-- keeping everything else as written: comments, order, spacing. Generic -
-- nothing here knows the game. For a file shaped like data/player.lua:
--   return {
--     name = {
--       key = "value",   -- a comment
--       sub = { key = ... },
--     },
--   }
--   E.set(text, { "name", "sub" }, "key", 'literal', "comment")
--     -> the new text, or nil and why
-- path: the tables from the file's own (the one returned), each a bare
-- name written `name = {` on its own line; a missing one is added. The key:
-- its line inside the last one is rewritten - only the value; the line's
-- comment stays. Not there: a line added at the end, with `comment`.
-- Refused (nil, why), the text unchanged: a value over several lines, the
-- same key twice, two entries on one line, long strings or comments
-- ([[ ]]), a table opened and closed on one line where something goes in.
--   E.literal(v)  a string, or a table of strings (a list, then named
--                 values: { "cmd", hit = "x" }), as Lua source
-- The caller checks the result reads back (load it): this is line-based.

local E = {}

-- One line, read: code (the comment taken off), where the comment starts
-- (nil: none), the brace depth before and after it. nil, why for what
-- isn't handled
local function scan_line(raw, depth)
  local code_end, comment_at = #raw, nil
  local i, q, n = 1, nil, #raw
  local d = depth
  while i <= n do
    local c = raw:sub(i, i)
    if q then
      if c == "\\" then i = i + 1
      elseif c == q then q = nil end
    elseif c == '"' or c == "'" then q = c
    elseif c == "[" and raw:sub(i + 1, i + 1):match("[%[=]") then
      return nil, "a long string"
    elseif c == "-" and raw:sub(i + 1, i + 1) == "-" then
      if raw:sub(i + 2, i + 3) == "[[" or raw:sub(i + 2, i + 3) == "[=" then return nil, "a long comment" end
      code_end, comment_at = i - 1, i
      break
    elseif c == "{" then d = d + 1
    elseif c == "}" then d = d - 1 end
    i = i + 1
  end
  if q then return nil, "a string over several lines" end
  return { raw = raw, code = raw:sub(1, code_end), comment = comment_at, before = depth, after = d }
end

local function scan(text)
  local lines, depth, no = {}, 0, 0
  for raw in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
    no = no + 1
    local L, why = scan_line(raw, depth)
    if not L then return nil, why .. " at line " .. no end
    lines[no] = L
    depth = L.after
  end
  return lines
end

local function blank(code) return code:match("^%s*$") ~= nil end
local function indent(s) return s:match("^(%s*)") end
local function esc(s) return (s:gsub("%p", "%%%0")) end

-- The table `name = {` among the children of (lo, hi) at depth: its open
-- and close lines, or nil
local function find_table(lines, lo, hi, depth, name)
  local pat = "^%s*" .. esc(name) .. "%s*=%s*{"
  for i = lo, hi do
    local L = lines[i]
    if L.before == depth and L.code:match(pat) then
      for j = i, hi do
        if lines[j].after == depth then return i, j end
      end
      return nil
    end
  end
end

-- After line k's code (before its comment), text added
local function append_code(L, s)
  local code = L.code:gsub("%s+$", "")
  local rest = L.raw:sub(#code + 1)
  L.raw = code .. s .. rest
  L.code = code .. s
end

-- A comma after the last entry before line j (so a new one can follow)
local function comma_before(lines, lo, j)
  for k = j - 1, lo, -1 do
    local code = lines[k].code:gsub("%s+$", "")
    if code ~= "" then
      if not code:match("[,{;]$") then append_code(lines[k], ",") end
      return
    end
  end
end

-- New lines put in before line j, at the indent the table's entries use
local function child_indent(lines, open, close, depth)
  for k = open + 1, close - 1 do
    local L = lines[k]
    if L.before == depth + 1 and not blank(L.code) then return indent(L.raw) end
  end
  return indent(lines[close].raw) .. "  "
end

local function insert(lines, j, new)
  for k = #new, 1, -1 do table.insert(lines, j, { raw = new[k], code = new[k], before = 0, after = 0 }) end
end

function E.literal(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for _, x in ipairs(v) do parts[#parts + 1] = E.literal(x) end
  local names = {}
  for k in pairs(v) do if type(k) == "string" then names[#names + 1] = k end end
  table.sort(names)
  for _, k in ipairs(names) do parts[#parts + 1] = k .. " = " .. E.literal(v[k]) end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

function E.set(text, path, key, literal, comment)
  local lines, why = scan(text)
  if not lines then return nil, why end
  -- the file's own table: the first line opening one at depth 0
  local open, close
  for i, L in ipairs(lines) do
    if L.before == 0 and L.after > 0 then open = i; break end
  end
  if not open then return nil, "no table in the file" end
  for j = open, #lines do
    if lines[j].after == 0 then close = j; break end
  end
  if not close or close == open then return nil, "the file's table isn't closed on a later line" end
  local depth = 1
  for _, name in ipairs(path) do
    local o, c = find_table(lines, open + 1, close - 1, depth, name)
    if o and o == c then return nil, name .. " is a table on one line (line " .. o .. ")" end
    if not o then
      -- not there: added at the end of its parent
      local ind = child_indent(lines, open, close, depth - 1)
      comma_before(lines, open, close)
      insert(lines, close, { ind .. name .. " = {", ind .. "},"})
      -- the new lines' depths, for the steps below
      lines[close].before, lines[close].after = depth, depth + 1
      lines[close + 1].before, lines[close + 1].after = depth + 1, depth
      o, c = close, close + 1
    end
    open, close, depth = o, c, depth + 1
  end
  -- the key's line among this table's entries
  local pat = "^(%s*" .. esc(key) .. "%s*=%s*)"
  local at
  for k = open + 1, close - 1 do
    local L = lines[k]
    if L.before == depth and L.code:match(pat) then
      if at then return nil, key .. " is there twice (lines " .. at .. " and " .. k .. ")" end
      at = k
    end
  end
  if at then
    local L = lines[at]
    if L.after ~= L.before then return nil, key .. "'s value goes over several lines (line " .. at .. ")" end
    local head = L.code:match(pat)
    local value = L.code:sub(#head + 1):gsub("%s+$", ""):gsub(",$", "")
    -- one entry on the line: its value alone reads as one expression
    local loader = loadstring or load
    if not loader("return " .. value) then return nil, "line " .. at .. " has more than " .. key .. " on it" end
    local code = L.code:gsub("%s+$", "")
    local gap = L.comment and L.raw:sub(#code + 1, L.comment - 1) or ""
    local tail = L.comment and L.raw:sub(L.comment) or ""
    L.raw = head .. literal .. "," .. gap .. tail
  else
    local ind = child_indent(lines, open, close, depth - 1)
    comma_before(lines, open, close)
    insert(lines, close, { ind .. key .. " = " .. literal .. "," .. (comment and ("   -- " .. comment) or "") })
  end
  local out = {}
  for i, L in ipairs(lines) do out[i] = L.raw end
  return table.concat(out, "\n") .. "\n"
end

return E
