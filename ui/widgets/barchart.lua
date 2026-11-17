-- panel:barchart { source, values, buckets, moments, sorted, labels, colors,
--                  zero, scale, cells, every }
-- A row per label: the label (right-aligned), a bar, the count.
--   values(v..., now) -> the counts, one per label (nil: no chart), and
--     optionally the seconds until one can change (ui/screen.lua's timed
--     widgets)
--   buckets: the rows' upper edges ({ 30, 60, 120 }) - values then returns
--     the numbers themselves, one per thing, and the chart counts them: a
--     number up to buckets[k] (and over the one before) in row k, over the
--     last in none
--   moments = true (with buckets): the numbers are moments (os.time); each
--     counts by the seconds left until it, one run out not at all; the
--     chart changes itself when one moves down a row
--   sorted = true (with buckets): the numbers come smallest first - the
--     counting stops at the first over the last bucket
--   scale: counts per full cell (the bar in eighths of a cell); cells: the
--     bar's width (10) - more than fits ends in an arrow
--   colors[k]: row k's color; zero: a row whose count is 0
-- A list (ui/screen.lua): each row compared on its own, only a changed one
-- formatted.
local screen = require("ui.screen")
local rep, bar, rpad, select = string.rep, screen.bar, screen.rpad, select
local NEVER = math.huge

-- values -> records: the numbers counted into the buckets
local function counter(values, edges, moments, sorted, nsrc)
  local n, c = #edges, {}   -- (one counts table: the list compares the rows by value)
  return function(...)
    local list, nxt = values(...)
    if list == nil then return nil, nxt end
    local now = moments and select(nsrc + 1, ...)
    for k = 1, n do c[k] = 0 end
    if moments then nxt = NEVER end
    for i = 1, #list do
      local x = list[i]
      if moments then x = x - now end
      if not moments or x > 0 then
        local k = 1
        while k <= n and x > edges[k] do k = k + 1 end
        if k <= n then c[k] = c[k] + 1 end
        if moments then   -- the seconds until it moves down a row (or runs out)
          local d = x - (edges[k - 1] or 0)
          if d < nxt then nxt = d end
        end
        if sorted and k > n then break end
      end
    end
    return c, nxt
  end
end

return screen.add_widget("barchart", function(panel, t)
  local labels, colors, zero = t.labels, t.colors or {}, t.zero
  local scale, cells, lw = t.scale or 1, t.cells or 10, 0
  for _, l in ipairs(labels) do if #l > lw then lw = #l end end
  local records = t.values
  if t.buckets then
    local src = t.source
    records = counter(t.values, t.buckets, t.moments, t.sorted, type(src) == "table" and #src or 1)
  end
  return panel:list {
    source = t.source, every = t.every, records = records,
    format = function(n, k)
      local text = rep(" ", lw - #labels[k]) .. labels[k] .. " " .. bar(n, scale, cells) .. " " .. rpad(tostring(n), 2)
      local c = n == 0 and zero or colors[k]
      return c and c(text) or text
    end,
  }
end)
