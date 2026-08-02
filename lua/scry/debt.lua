-- Theory-debt: separate numbers, never one blended fraction. Unratified
-- and diverged are different kinds of wrongness, and the claim count leads
-- every rendering — "0 diverged / 3 claims" must read as a THIN map, not a
-- healthy repo. Debt is coverage-blind until exists-unclaimed lands, and
-- the docs say so.
local M = {}

---@class scry.Debt
---@field claims integer
---@field backed integer  backed or clean verdicts.
---@field missing integer
---@field violated integer
---@field unchecked integer no resolver, parse failure, resolver error, or no
---  verdict at all. NOT a pass — the fourth column exists so this can never
---  be inferred by subtraction.
---@field untouched integer no work has passed through this claim: not
---  authored by hand, not conjured to completion. Ownership is INFERRED
---  from the trail (see provenance.lua), never performed as an act.
---@field features integer
---@field done integer      features whose every claim holds AND that someone
---  here has engaged with.
---@field unread integer    features whose every claim holds and that nobody
---  has read: a fresh draft, or a map you have just cloned. Counted apart
---  from `done` because otherwise the first line of the header reports a
---  finished product on evidence nobody has looked at.
---@field building integer  features with some evidence, none broken.
---@field broken integer    features with a violated or failing claim.
---@field todo integer      features with no evidence holding yet.
---@field unknown integer   features nothing has answered for.
---@field unclaimed integer  files no feature's footprint names. Reflexion's
---  third verdict: without it, every feature can be done while the map
---  describes a tenth of the product, and nothing would say so.

--- Count a map + report into debt numbers. A claim can count on both the
--- diverged and unratified axes; each axis counts it once.
---
--- backed + missing + violated + unchecked == claims, always. That identity
--- is the honesty property: a claim no engine could answer must show up
--- somewhere, or a header reading "0 missing · 0 violated" invites the reader
--- to conclude the rest are fine.
---@param map_ scry.Map
---@param report scry.Report?
---@param root string? Project root; without it nothing counts as owned, and
---  divergence cannot be computed.
---@return scry.Debt
function M.count(map_, report, root)
  local mapmod = require("scry.map")
  local prov = require("scry.provenance")
  local counts = require("scry.feature").tally(map_, report, root)
  local d = {
    claims = #map_.claims,
    backed = 0,
    missing = 0,
    violated = 0,
    unchecked = 0,
    untouched = 0,
    features = #map_.features,
    done = counts.done,
    unread = counts.unread,
    building = counts.partial,
    broken = counts.broken,
    todo = counts.absent + counts.unevidenced,
    unknown = counts.unknown,
    unclaimed = 0,
  }
  -- Divergence needs the filesystem, so it is best-effort: a repo without
  -- ripgrep, or a root that has gone away, must not take the whole header
  -- down with it.
  if root then
    local ok, div = pcall(function()
      return (require("scry.divergence").unclaimed(root, map_, require("scry.project").resolve(root)))
    end)
    if ok then
      d.unclaimed = #div
    end
  end

  for _, claim in ipairs(map_.claims) do
    if not (root and prov.owned(root, claim)) then
      d.untouched = d.untouched + 1
    end
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    local status = v and v.status
    if status == "backed" or status == "clean" then
      d.backed = d.backed + 1
    elseif status == "missing" then
      d.missing = d.missing + 1
    elseif status == "violated" then
      d.violated = d.violated + 1
    else
      -- unchecked, error, an unknown status, or no verdict at all
      d.unchecked = d.unchecked + 1
    end
  end
  return d
end

--- Header for the glass.
---
--- Features lead, because the reader's question is what the product does —
--- not how many subfunctions resolved. Claim-level numbers follow on a
--- second line: they are the evidence behind the first, and reading them
--- first is the altitude mistake the whole map exists to avoid.
---@param d scry.Debt
---@param at integer? report timestamp
---@return string
function M.header(d, at)
  local age = at and (os.time() - at) or nil
  local when = age == nil and "unchecked" or (age < 5 and "just checked" or ("checked " .. age .. "s ago"))
  -- The unchecked column is shown whenever it is non-zero, between violated
  -- and unratified: nothing an engine declined to answer may be omitted from
  -- the one line the reader actually glances at.
  local parts = { ("%d features"):format(d.features) }
  local function add(n, word)
    if n > 0 then
      parts[#parts + 1] = ("%d %s"):format(n, word)
    end
  end
  add(d.done, "done")
  -- Immediately after done, and before anything else: this is the number that
  -- keeps "N done" from being read as "N finished".
  add(d.unread, "unread")
  add(d.building, "building")
  add(d.broken, "broken")
  add(d.todo, "to do")
  add(d.unknown, "unknown")
  add(d.unclaimed, "unclaimed files")
  local unchecked = d.unchecked > 0 and (" · %d unchecked"):format(d.unchecked) or ""
  local fmt = "scry · %s   %s (files on disk)"
    .. "\n      %d claims · %d backed · %d missing · %d violated%s · %d untouched"
  return fmt:format(
    table.concat(parts, " · "),
    when,
    d.claims,
    d.backed,
    d.missing,
    d.violated,
    unchecked,
    d.untouched
  )
end

--- The header, formatted for a window bar.
---
--- The glass header used to be virtual lines above line 1, which Neovim
--- never draws: there is no room above the first line of a buffer, so the
--- header was invisible on exactly the map everyone sees first. A winbar has
--- no such problem, and gains something the virtual lines never had — it
--- stays put while you scroll, so the counts are readable from anywhere in a
--- long map rather than only from the top.
---
--- One line instead of two, FITTED rather than truncated.
---
--- `%<` was tried both ways and neither works here. In the middle, Vim keeps
--- the tail and eats the words before it: a real window rendered
--- `(files on disk)<issing · 0 violated`, the counts sliced in half. At the
--- end, the winbar renders EMPTY — the option was set and the function
--- returned a full string, and the bar was blank.
---
--- So the segments are joined only if they fit. Features first, because that
--- is what a reader scans, and the claim-level evidence is what a narrow
--- window gives up. The ellipsis says it was cut, since cut off must not read
--- as absent — the distinction the unchecked column exists for.
---@param d scry.Debt
---@param at integer? report timestamp
---@param width integer? columns available; unlimited when nil
---@return string
function M.winbar(d, at, width)
  local lines = vim.split(M.header(d, at), "\n", { plain = true })
  local head, tail = vim.trim(lines[1] or ""), vim.trim(lines[2] or "")
  local function esc(s)
    return (s:gsub("%%", "%%%%"))
  end
  local joined = head .. "  ·  " .. tail
  if width and width > 2 and vim.fn.strdisplaywidth(joined) > width then
    if vim.fn.strdisplaywidth(head) > width then
      joined = vim.fn.strcharpart(head, 0, width - 1) .. "…"
    else
      joined = head .. " …"
    end
  end
  return "%#ScryHeader#" .. esc(joined) .. "%*"
end

--- Compact string for the user's own statusline. Plain function, no
--- statusline framework: `scry 9f ✓6 ◐2 ✗1 ∅3` — features first. The `–` count appears only
--- when something went unchecked, for the same reason the header carries it:
--- `✗0` must not be readable as "everything is accounted for". Unread
--- features fold into the `◐` count rather than the `✓` one: in six
--- characters the only thing worth preserving is that they are not finished.
---@return string
function M.statusline()
  local glass = require("scry.glass")
  local d = glass.current_debt()
  if not d then
    return ""
  end
  local unchecked = d.unchecked > 0 and (" –%d"):format(d.unchecked) or ""
  return ("scry %df ✓%d ◐%d ✗%d%s ∅%d"):format(
    d.features,
    d.done,
    d.building + d.unread,
    d.broken + d.todo,
    unchecked,
    d.untouched
  )
end

return M
