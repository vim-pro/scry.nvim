-- A feature's state, derived from its evidence.
--
-- Nothing here is authored. You write the feature and the claims that back
-- it; the state is what those claims currently say, rolled up. That is the
-- whole point of putting features at the top: the reader wants to know
-- whether the product does this thing, not how four subfunctions resolved.
--
-- The order of the tests is the priority order for a reader. A regression
-- outranks incomplete work — a feature that used to hold and now doesn't
-- is the most urgent line on the page — and incomplete work outranks
-- nothing-yet, because partial work is in flight and needs finishing.
--
-- "partial" requires REAL progress: at least one claim actually holding.
-- A feature whose claims were simply never answered is `unknown`, not
-- partial, because partial implies you are part of the way there. Before
-- the first check settles every feature is in exactly that state, and
-- showing it as progress would be a lie told at the least useful moment.
--
-- "unread" outranks "done", and it exists because the evidence axis and the
-- engagement axis are different questions. Every claim under a feature can
-- hold while nobody has read a word of it — which is precisely the state a
-- drafting pass produces, and dogfooding the pass produced it immediately:
-- two features, both `✓ done`, one of them written by a machine thirty
-- seconds earlier. The untouched count said so on the second line, and the
-- second line is not the line anybody scans.
--
-- So a feature whose every claim is untouched cannot read done. It reads
-- `– unread`, and the wording covers the other way into this state too: a
-- map you have just cloned. The trail is per-machine and unversioned, so
-- someone else's understanding does not arrive with their file — which is
-- the whole reason the theory cannot be externalised, and `unread` is a true
-- sentence about a map you have never opened.
--
-- Deliberately narrow: `unread` displaces `done` only. A half-backed feature
-- nobody has touched still reads `◐ 2 of 5`, because progress is the more
-- useful reading and it is not claiming to be finished. The lie worth
-- closing is the claim of completion.
local M = {}

---@alias scry.FeatureState "done"|"broken"|"unread"|"partial"|"unknown"|"absent"|"unevidenced"

---@class scry.FeatureVerdict
---@field state scry.FeatureState
---@field label string Rendered wording, honesty-load-bearing like a claim's.
---@field backed integer
---@field total integer

--- Roll a feature's claim verdicts into one state.
---@param feature scry.Feature
---@param report scry.Report?
---@param root string? Project root. Without it engagement cannot be read, so
---  `unread` is never reported — a caller with no root gets the evidence axis
---  only, which is honest about what it could see.
---@return scry.FeatureVerdict
function M.verdict(feature, report, root)
  local mapmod = require("scry.map")
  local total = #feature.claims
  if total == 0 then
    -- Prose with nothing checkable under it. Not a failure — it is how a
    -- feature looks the moment you name it — but it is not evidence either,
    -- and a map full of these is a wish list.
    return { state = "unevidenced", label = "– no evidence yet", backed = 0, total = 0 }
  end

  local backed, broken, unchecked = 0, 0, 0
  for _, claim in ipairs(feature.claims) do
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    local status = v and v.status
    if status == "backed" or status == "clean" then
      backed = backed + 1
    elseif status == "violated" then
      broken = broken + 1
    elseif status ~= "missing" then
      unchecked = unchecked + 1
    end
  end

  if broken > 0 then
    return {
      state = "broken",
      label = ("✗ broken (%d of %d)"):format(broken, total),
      backed = backed,
      total = total,
    }
  end
  if backed == total then
    if root and not M.engaged(root, feature) then
      return {
        state = "unread",
        -- Same shape as every other state, so the column has one rhythm:
        -- `– unread 3 of 3` reads beside `◐ 2 of 4`, where
        -- `– unread (3 of 3 backed)` was half again as long and broke it.
        label = ("– unread %d of %d"):format(backed, total),
        backed = backed,
        total = total,
      }
    end
    return { state = "done", label = "✓ done", backed = backed, total = total }
  end
  if backed > 0 then
    return {
      state = "partial",
      label = ("◐ %d of %d"):format(backed, total),
      backed = backed,
      total = total,
    }
  end
  if unchecked > 0 then
    return {
      state = "unknown",
      label = ("– unchecked (%d of %d)"):format(unchecked, total),
      backed = 0,
      total = total,
    }
  end
  return { state = "absent", label = "✗ not yet", backed = 0, total = total }
end

--- Has anyone here engaged with any part of this feature?
---
--- Any single owned claim is enough. The question is whether a human has been
--- through this description at all, not whether they finished — one edited
--- claim means the feature was read, and holding out for all of them would
--- report `unread` for work visibly in progress.
---@param root string
---@param feature scry.Feature
---@return boolean
function M.engaged(root, feature)
  local prov = require("scry.provenance")
  for _, claim in ipairs(feature.claims) do
    if prov.owned(root, claim) then
      return true
    end
  end
  return false
end

--- Count features by state, for the header.
---@param map_ scry.Map
---@param report scry.Report?
---@param root string?
---@return table<scry.FeatureState, integer> counts, integer total
function M.tally(map_, report, root)
  local counts = { done = 0, broken = 0, unread = 0, partial = 0, unknown = 0, absent = 0, unevidenced = 0 }
  for _, feature in ipairs(map_.features) do
    local v = M.verdict(feature, report, root)
    counts[v.state] = counts[v.state] + 1
  end
  return counts, #map_.features
end

return M
