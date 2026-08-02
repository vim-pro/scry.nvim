-- Reflexion: run every claim in a map through the resolver, settle once,
-- and hand back a timestamped report. The report is the ONLY thing the
-- renderer trusts — a verdict is always presented with when it was
-- computed and against what (files on disk).
local M = {}

---@class scry.Report
---@field at integer os.time() when the check settled.
---@field verdicts table<string, scry.Verdict> Keyed by map.claim_id.

-- The vacuity gate.
--
-- Written before the code it checks, a spec must FAIL. One that passes
-- against a feature nobody has built is asserting nothing — the commonest
-- way a conjured test is worthless, and invisible from inside the run: the
-- process exits 0 either way.
--
-- Individual verdicts can't see this, because each claim is checked alone. So
-- it is a pass over the settled report: within a feature, a passing spec is
-- downgraded when EVERY structural claim there is still absent. Deliberately
-- conservative — a feature that is half-built has plenty for a spec to
-- legitimately exercise, and a false "vacuous" would train you to ignore it.
---@param map_ scry.Map
---@param report scry.Report
local function gate_vacuity(map_, report)
  local mapmod = require("scry.map")
  local structural, exercised = {}, {}
  for _, claim in ipairs(map_.claims) do
    local v = report.verdicts[mapmod.claim_id(claim)]
    if claim.kind == "def" or claim.kind == "module" then
      structural[claim.feature] = structural[claim.feature] or { total = 0, absent = 0 }
      local s = structural[claim.feature]
      s.total = s.total + 1
      if v and v.status == "missing" then
        s.absent = s.absent + 1
      end
    elseif claim.kind == "exercises" and v and v.status == "backed" then
      exercised[#exercised + 1] = claim
    end
  end
  for _, claim in ipairs(exercised) do
    local s = structural[claim.feature]
    if s and s.total > 0 and s.absent == s.total then
      report.verdicts[mapmod.claim_id(claim)] = {
        status = "unchecked",
        fidelity = "run",
        label = "– vacuous? it passes, and nothing this feature claims exists yet",
      }
    end
  end
end

--- Check `claims` (default: all of the map's) and cb(report) once settled.
---@param map_ scry.Map
---@param opts { root: string, resolver: scry.Resolver?, claims: scry.Claim[]? }
---@param cb fun(report: scry.Report)
function M.run(map_, opts, cb)
  local mapmod = require("scry.map")
  local resolver = opts.resolver or require("scry.resolver").get()
  local claims = opts.claims or map_.claims

  local report = { at = os.time(), verdicts = {} }
  local function settle()
    report.at = os.time()
    -- Only meaningful over a whole map; a partial check (the cascade's
    -- scoped re-check) has no view of the feature's other claims.
    if not opts.claims then
      gate_vacuity(map_, report)
    end
    cb(report)
  end

  local pending = #claims
  if pending == 0 then
    settle()
    return
  end

  -- A claim is checked in the scope of its own feature's footprint: the
  -- files that feature's located claims name. Derived, so it cannot drift
  -- from the claims it describes — and empty when a feature locates
  -- nothing, which the resolver reports rather than papering over by
  -- searching the whole project.
  -- The kinds in force, so the resolver can check a declared kind by the
  -- probe the project wrote for it.
  local kindset = require("scry.map").kinds_for(opts.root)
  local scope = {}
  for _, feature in ipairs(map_.features) do
    -- With the kinds in force, so a never-claim's scope covers the pages
    -- and endpoints the feature is made of and not just its .lua files.
    scope[feature.name] = mapmod.footprint(feature, kindset)
  end

  for _, claim in ipairs(claims) do
    local ctx = { root = opts.root, globs = scope[claim.feature] or {}, kinds = kindset }
    require("scry.resolver").check(resolver, ctx, claim, function(verdict)
      report.verdicts[mapmod.claim_id(claim)] = verdict
      pending = pending - 1
      if pending == 0 then
        settle()
      end
    end)
  end
end

return M
