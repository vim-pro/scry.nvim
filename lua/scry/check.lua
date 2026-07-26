-- Reflexion: run every claim in a map through the resolver, settle once,
-- and hand back a timestamped report. The report is the ONLY thing the
-- renderer trusts — a verdict is always presented with when it was
-- computed and against what (files on disk).
local M = {}

---@class scry.Report
---@field at integer os.time() when the check settled.
---@field verdicts table<string, scry.Verdict> Keyed by map.claim_id.

--- Check `claims` (default: all of the map's) and cb(report) once settled.
---@param map_ scry.Map
---@param opts { root: string, resolver: scry.Resolver?, claims: scry.Claim[]? }
---@param cb fun(report: scry.Report)
function M.run(map_, opts, cb)
  local mapmod = require("scry.map")
  local resolver = opts.resolver or require("scry.resolver").get()
  local claims = opts.claims or map_.claims

  local report = { at = os.time(), verdicts = {} }
  local pending = #claims
  if pending == 0 then
    cb(report)
    return
  end

  for _, claim in ipairs(claims) do
    local concern = mapmod.concern(map_, claim.concern)
    local ctx = { root = opts.root, globs = concern and concern.globs or {} }
    require("scry.resolver").check(resolver, ctx, claim, function(verdict)
      report.verdicts[mapmod.claim_id(claim)] = verdict
      pending = pending - 1
      if pending == 0 then
        report.at = os.time()
        cb(report)
      end
    end)
  end
end

return M
