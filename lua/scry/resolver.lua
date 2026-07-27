-- The resolver interface: the seam between the glass and whatever engine
-- decides claims. v0 ships ts_rg (treesitter definitions + ripgrep text
-- search); LSP or stack-graph engines replace it later without the glass
-- changing. Fidelity travels WITH the verdict — the renderer cannot use a
-- stronger word than the engine that produced the evidence.
local M = {}

---@class scry.Evidence
---@field path string Repo-root-relative.
---@field lnum integer
---@field text string The matching line, trimmed.

---@class scry.Verdict
---@field status "backed"|"missing"|"violated"|"clean"|"unchecked"|"error"
---@field fidelity "ts-def"|"rg-text"|"run"|"none" What kind of evidence backs
---  this. "run" is the dynamic class: produced by executing something rather
---  than reading it, and therefore the only one that can be stale while
---  still looking authoritative. Anything with fidelity "run" must render
---  its age.
---@field label string Exact rendered wording — resolver-owned, honesty-load-bearing.
---@field evidence scry.Evidence[]? lnum 0 = no line to point at (run output).

---@class scry.Ctx
---@field root string Absolute project root.
---@field globs string[] The concern's files globs (rg -g syntax).

---@class scry.Resolver
---@field name string
---@field check_contains fun(ctx: scry.Ctx, claim: scry.Claim, cb: fun(v: scry.Verdict))
---@field check_calls fun(ctx: scry.Ctx, claim: scry.Claim, cb: fun(v: scry.Verdict))
---@field check_never fun(ctx: scry.Ctx, claim: scry.Claim, cb: fun(v: scry.Verdict))
---@field check_exercises fun(ctx: scry.Ctx, claim: scry.Claim, cb: fun(v: scry.Verdict))
---  MUST NOT execute anything. It reports what the last |:ScryExercise| recorded.

local registry = {}

---@param resolver scry.Resolver
function M.register(resolver)
  registry[resolver.name] = resolver
end

---@param name string?
---@return scry.Resolver
function M.get(name)
  if name and registry[name] then
    return registry[name]
  end
  return require("scry.resolvers.ts_rg")
end

--- Dispatch a claim to the right check on `resolver`.
---@param resolver scry.Resolver
---@param ctx scry.Ctx
---@param claim scry.Claim
---@param cb fun(v: scry.Verdict)
function M.check(resolver, ctx, claim, cb)
  local fn = resolver["check_" .. claim.kind]
  if not fn then
    cb({ status = "error", fidelity = "none", label = "– unknown claim kind" })
    return
  end
  local ok, err = pcall(fn, ctx, claim, cb)
  if not ok then
    cb({ status = "error", fidelity = "none", label = "– resolver error: " .. tostring(err) })
  end
end

return M
