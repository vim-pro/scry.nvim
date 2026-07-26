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
---@field unratified integer no stamp, or stamp stale against current text.

--- Count a map + report into debt numbers. A claim can count on both the
--- diverged and unratified axes; each axis counts it once.
---@param map_ scry.Map
---@param report scry.Report?
---@return scry.Debt
function M.count(map_, report)
  local mapmod = require("scry.map")
  local ratify = require("scry.ratify")
  local d = { claims = #map_.claims, backed = 0, missing = 0, violated = 0, unratified = 0 }
  for _, claim in ipairs(map_.claims) do
    if not ratify.ratified(claim) then
      d.unratified = d.unratified + 1
    end
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    if v then
      if v.status == "backed" or v.status == "clean" then
        d.backed = d.backed + 1
      elseif v.status == "missing" then
        d.missing = d.missing + 1
      elseif v.status == "violated" then
        d.violated = d.violated + 1
      end
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
  return ("scry · %d claims · %d backed · %d missing · %d violated · %d unratified   %s (files on disk)"):format(
    d.claims,
    d.backed,
    d.missing,
    d.violated,
    d.unratified,
    when
  )
end

--- Compact string for the user's own statusline. Plain function, no
--- statusline framework: `scry 14c ✓11 ✗2 ∅3`.
---@return string
function M.statusline()
  local glass = require("scry.glass")
  local d = glass.current_debt()
  if not d then
    return ""
  end
  return ("scry %dc ✓%d ✗%d ∅%d"):format(d.claims, d.backed, d.missing + d.violated, d.unratified)
end

return M
