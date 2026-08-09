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
-- THERE IS ONE AXIS HERE, AND IT IS EVIDENCE. The state says only what the
-- evidence says.
local M = {}

-- The engine's own ladder, weakest first. `run` is the only rung that says
-- anything was EXECUTED; everything under it is structure.
local ORDER = { none = 0, file = 1, ["rg-text"] = 2, ["text-def"] = 3, ["ts-def"] = 4, run = 5 }

-- What a whole feature at that rung has actually established. Never a word
-- stronger than the engine's own — the same rule the labels follow.
local WORDING = {
  file = "✓ %d files exist",
  ["rg-text"] = "✓ %d hold (text)",
  -- A text definition could be in a comment; the parser cannot be wrong
  -- about that. Same word, and the qualifier is what separates them.
  ["text-def"] = "✓ %d defined (text)",
  ["ts-def"] = "✓ %d defined",
}

--- The floor and the ceiling of a feature's evidence.
---
--- TWO QUESTIONS, NOT ONE. "Was any of this executed" and "how well is the
--- rest established" are the two axes the map is built on (|scry-exercised|),
--- and they do not combine into a single minimum.
---
--- A run PROMOTES: a spec that passed is behavioral evidence, and the
--- structural claims beside it are supporting detail — taking the minimum
--- would mean a feature could never be `done` unless every member were
--- somehow itself an execution.
---
--- With nothing executed, the FLOOR is what the feature has: it cannot be
--- better established than its least-established part.
---@param feature scry.Feature
---@param report scry.Report?
---@return string floor, string ceiling
local function rungs(feature, report)
  local mapmod = require("scry.map")
  local low, high = nil, nil
  for _, claim in ipairs(feature.claims) do
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    local f = v and v.fidelity or "none"
    if not low or (ORDER[f] or 0) < (ORDER[low] or 0) then
      low = f
    end
    if not high or (ORDER[f] or 0) > (ORDER[high] or 0) then
      high = f
    end
  end
  return low or "none", high or "none"
end

---@alias scry.FeatureState "done"|"in_place"|"broken"|"partial"|"unknown"|"absent"|"unevidenced"

---@class scry.FeatureVerdict
---@field state scry.FeatureState
---@field label string Rendered wording, honesty-load-bearing like a claim's.
---@field backed integer
---@field total integer
---@field rung string? The WEAKEST fidelity among the claims that hold.

--- Roll a feature's claim verdicts into one state.
---@param feature scry.Feature
---@param report scry.Report?
---@param root string? Unused; kept so every caller does not change shape.
---@return scry.FeatureVerdict
function M.verdict(feature, report, root) -- luacheck: ignore root
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
    -- A FEATURE IS ONLY AS STRONG AS ITS WEAKEST CLAIM.
    --
    -- This rolled everything that held up to `✓ done`, whatever it was that
    -- held. Measured on a real map: three members, each a `module <path>`
    -- claim asserting a file is on disk — all three files predating the
    -- capability by months — and the feature read `✓ done`. The reader's
    -- question was "does this mean the feature already exists", and the
    -- honest answer was no: three files exist, and nothing has looked inside
    -- any of them.
    --
    -- The rungs are the engine's own (scry.resolver: file < rg-text < ts-def
    -- < run). Rolling four `present (file)` verdicts up into the strongest
    -- word on the page laundered the weakest evidence there is.
    --
    -- `done` now costs a RUN. Everything below it says what it actually is.
    local floor, ceiling = rungs(feature, report)
    if ceiling == "run" then
      return { state = "done", label = "✓ done", backed = backed, total = total, rung = "run" }
    end
    return {
      state = "in_place",
      label = (WORDING[floor] or "✓ %d backed"):format(total),
      backed = backed,
      total = total,
      rung = floor,
    }
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

--- Count features by state, for the header.
---@param map_ scry.Map
---@param report scry.Report?
---@param root string?
---@return table<scry.FeatureState, integer> counts, integer total
function M.tally(map_, report, root)
  local counts = { done = 0, in_place = 0, broken = 0, partial = 0, unknown = 0, absent = 0, unevidenced = 0 }
  for _, feature in ipairs(map_.features) do
    local v = M.verdict(feature, report, root)
    counts[v.state] = counts[v.state] + 1
  end
  return counts, #map_.features
end

return M
