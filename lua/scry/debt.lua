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
---@field done integer      features whose every claim holds.
---@field building integer  features with some evidence, none broken.
---@field broken integer    features with a violated or failing claim.
---@field todo integer      features with no evidence holding yet.
---@field unknown integer   features nothing has answered for.

--- Count a map + report into debt numbers. A claim can count on both the
--- diverged and unratified axes; each axis counts it once.
---
--- backed + missing + violated + unchecked == claims, always. That identity
--- is the honesty property: a claim no engine could answer must show up
--- somewhere, or a header reading "0 missing · 0 violated" invites the reader
--- to conclude the rest are fine.
---@param map_ scry.Map
---@param report scry.Report?
---@param root string? Project root; without it nothing counts as owned.
---@return scry.Debt
function M.count(map_, report, root)
  local mapmod = require("scry.map")
  local prov = require("scry.provenance")
  local counts = require("scry.feature").tally(map_, report)
  local d = {
    claims = #map_.claims,
    backed = 0,
    missing = 0,
    violated = 0,
    unchecked = 0,
    untouched = 0,
    features = #map_.features,
    done = counts.done,
    building = counts.partial,
    broken = counts.broken,
    todo = counts.absent + counts.unevidenced,
    unknown = counts.unknown,
  }
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
  add(d.building, "building")
  add(d.broken, "broken")
  add(d.todo, "to do")
  add(d.unknown, "unknown")
  local unchecked = d.unchecked > 0 and (" · %d unchecked"):format(d.unchecked) or ""
  return ("scry · %s   %s (files on disk)\n      %d claims · %d backed · %d missing · %d violated%s · %d untouched"):format(
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

--- Compact string for the user's own statusline. Plain function, no
--- statusline framework: `scry 9f ✓6 ◐2 ✗1 ∅3` — features first. The `–` count appears only
--- when something went unchecked, for the same reason the header carries it:
--- `✗0` must not be readable as "everything is accounted for".
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
    d.building,
    d.broken + d.todo,
    unchecked,
    d.untouched
  )
end

return M
