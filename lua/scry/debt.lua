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
---@field unratified integer no stamp, or stamp stale against current text.

--- Count a map + report into debt numbers. A claim can count on both the
--- diverged and unratified axes; each axis counts it once.
---
--- backed + missing + violated + unchecked == claims, always. That identity
--- is the honesty property: a claim no engine could answer must show up
--- somewhere, or a header reading "0 missing · 0 violated" invites the reader
--- to conclude the rest are fine.
---@param map_ scry.Map
---@param report scry.Report?
---@return scry.Debt
function M.count(map_, report)
  local mapmod = require("scry.map")
  local ratify = require("scry.ratify")
  local d = { claims = #map_.claims, backed = 0, missing = 0, violated = 0, unchecked = 0, unratified = 0 }
  for _, claim in ipairs(map_.claims) do
    if not ratify.ratified(claim) then
      d.unratified = d.unratified + 1
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

--- Header line for the glass.
---@param d scry.Debt
---@param at integer? report timestamp
---@return string
function M.header(d, at)
  local age = at and (os.time() - at) or nil
  local when = age == nil and "unchecked" or (age < 5 and "just checked" or ("checked " .. age .. "s ago"))
  -- The unchecked column is shown whenever it is non-zero, between violated
  -- and unratified: nothing an engine declined to answer may be omitted from
  -- the one line the reader actually glances at.
  local unchecked = d.unchecked > 0 and (" · %d unchecked"):format(d.unchecked) or ""
  return ("scry · %d claims · %d backed · %d missing · %d violated%s · %d unratified   %s (files on disk)"):format(
    d.claims,
    d.backed,
    d.missing,
    d.violated,
    unchecked,
    d.unratified,
    when
  )
end

--- Compact string for the user's own statusline. Plain function, no
--- statusline framework: `scry 14c ✓11 ✗2 –1 ∅3`. The `–` count appears only
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
  return ("scry %dc ✓%d ✗%d%s ∅%d"):format(d.claims, d.backed, d.missing + d.violated, unchecked, d.unratified)
end

return M
