-- The ts_rg resolver against the fixture, from disk: every verdict kind,
-- with its fidelity, label, and evidence.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

if vim.fn.executable("rg") ~= 1 then
  H.fail("ripgrep is required for the resolver (and this spec)")
end

local resolver = require("scry.resolver")
local ts_rg = require("scry.resolvers.ts_rg")
local map = require("scry.map")

local m = map.load(H.fixture .. "/map.scry")
local hold = map.load(H.fixture .. "/holdout.scry")
local S1 = "a user can start a session"
local S2 = "a session can be refreshed"

-- Each feature scopes its own claims now, so the ctx is per-feature and
-- derived — never a declared glob.
local function ctx_for(feature_name)
  local f = map.feature(m, feature_name) or map.feature(hold, feature_name)
  return { root = H.fixture, globs = f and map.footprint(f) or {} }
end

-- Collect verdicts for a list of claims synchronously.
local function decide(claims)
  local out, pending = {}, #claims
  for _, claim in ipairs(claims) do
    resolver.check(ts_rg, ctx_for(claim.feature), claim, function(v)
      out[map.claim_id(claim)] = v
      pending = pending - 1
    end)
  end
  H.ok(H.wait(function()
    return pending == 0
  end), "all verdicts settled")
  return out
end

local verdicts = decide(m.claims)
-- The holdout carries only never-patterns, which locate nothing; their scope
-- comes from the map feature of the same name.
local hv = decide(hold.claims)

local function v(kind, target)
  for _, feature in ipairs({ S1, S2 }) do
    local id = feature .. "\1" .. kind .. "\1" .. target
    if verdicts[id] then
      return verdicts[id]
    end
    if hv[id] then
      return hv[id]
    end
  end
end

-- contains
H.eq(v("contains", "lua/auth.lua:create_session").status, "backed", "create_session defined")
H.eq(v("contains", "lua/auth.lua:create_session").label, "✓ defined", "contains label")
H.eq(v("contains", "lua/auth.lua:create_session").fidelity, "ts-def", "contains fidelity")
H.eq(v("contains", "lua/auth.lua:validate_token").status, "backed", "validate_token defined")
H.eq(v("contains", "lua/auth.lua:refresh_token").status, "missing", "refresh_token absent")
H.eq(v("contains", "lua/auth.lua:refresh_token").label, "✗ absent", "absent label")

-- calls: backed / absent / unreferenced are three distinct outcomes
H.eq(v("calls", "store.lua::put").status, "backed", "store.put referenced")
H.eq(v("calls", "store.lua::put").label, "✓ referenced (text)", "calls label states text fidelity")
H.eq(v("calls", "store.lua::put").fidelity, "rg-text", "calls fidelity")
H.ok(#v("calls", "store.lua::put").evidence > 0, "reference evidence attached")
H.eq(v("calls", "crypto.lua::verify").status, "missing", "crypto.verify absent (no such module)")
H.eq(v("calls", "crypto.lua::verify").label, "✗ absent", "absent calls label")
H.eq(v("calls", "store.lua::purge").status, "missing", "purge defined but unreferenced")
H.eq(v("calls", "store.lua::purge").label, "✗ unreferenced", "unreferenced label distinct from absent")

-- never: violated with evidence; clean
local viol = v("never", "logging\\.debug")
H.eq(viol.status, "violated", "logging.debug violated")
H.eq(viol.label, "✗ VIOLATED", "violation label")
H.eq(viol.evidence[1].path, "lua/auth.lua", "evidence path")
H.eq(viol.evidence[1].lnum, 9, "evidence line number")
H.ok(viol.evidence[1].text:find("logging.debug", 1, true) ~= nil, "evidence text")
local clean = v("never", "io\\.write")
H.eq(clean.status, "clean", "io.write clean (logging.lua is outside the feature's files)")
H.eq(clean.label, "✓ no matches (rg)", "clean label states rg fidelity")

-- non-lua contains → unchecked, never ✓
local unch = {}
resolver.check(ts_rg, ctx, { kind = "contains", target = "src/main.rs:run", feature = "a user can start a session" }, function(x)
  unch = x
end)
H.ok(H.wait(function()
  return unch.status ~= nil
end), "unchecked settled")
H.eq(unch.status, "unchecked", "non-lua target is unchecked")
H.eq(unch.label, "– unchecked (no lua resolver)", "unchecked label — silence never masquerades as ✓")

H.done("resolver_spec PASS")
