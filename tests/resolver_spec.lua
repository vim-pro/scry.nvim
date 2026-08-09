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
local S1 = "a user can start a session"
local S2 = "a session can be refreshed"

-- Each feature scopes its own claims now, so the ctx is per-feature and
-- derived — never a declared glob.
local function ctx_for(feature_name)
  local f = map.feature(m, feature_name)
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

local function v(kind, target)
  for _, feature in ipairs({ S1, S2 }) do
    local id = feature .. "\1" .. kind .. "\1" .. target
    if verdicts[id] then
      return verdicts[id]
    end
  end
end

-- contains
H.eq(v("def", "lua/auth.lua:create_session").status, "backed", "create_session defined")
H.eq(v("def", "lua/auth.lua:create_session").label, "✓ defined", "contains label")
H.eq(v("def", "lua/auth.lua:create_session").fidelity, "ts-def", "contains fidelity")
H.eq(v("def", "lua/auth.lua:validate_token").status, "backed", "validate_token defined")
H.eq(v("def", "lua/auth.lua:refresh_token").status, "missing", "refresh_token absent")
H.eq(v("def", "lua/auth.lua:refresh_token").label, "✗ absent", "absent label")

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

-- A `def` IS ANSWERABLE IN EVERY LANGUAGE, at one of two rungs.
--
-- It used to be lua or nothing: anything else answered `– unchecked (no lua
-- resolver)` forever. Measured on a real project — Astro and TypeScript —
-- that made every claim scry could offer top out at "the file is on disk",
-- because the one rung above it was closed. A tool that can only describe
-- lua is a lua tool.
--
-- There is no TypeScript grammar on the machines this suite runs on, which
-- is exactly the case worth pinning: this is what most of most projects looks
-- like to scry.
local function decide_one(target)
  local got = {}
  resolver.check(ts_rg, ctx_for(S1), { kind = "def", target = target, feature = S1 }, function(x)
    got = x
  end)
  H.ok(H.wait(function()
    return got.status ~= nil
  end), "settled: " .. target)
  return got
end

local textual = decide_one("web/print.ts:renderPrintSheet")
H.eq(textual.status, "backed", "a TypeScript definition is found")
H.eq(textual.fidelity, "text-def", "at the TEXT rung, because there is no grammar for it here")
H.eq(textual.label, "✓ defined (text)", "and the label says which rung answered")

-- THE LABEL IS THE HONESTY. `✓ defined` is a definition NODE; `✓ defined
-- (text)` is a line that looks like one and could be sitting in a comment.
-- Same status, different claim, and a reader has to be able to tell.
local parsed = decide_one("lua/auth.lua:create_session")
H.eq(parsed.fidelity, "ts-def", "lua still gets the parsed rung")
H.eq(parsed.label, "✓ defined", "with no qualifier, because none is needed")
H.ok(textual.label ~= parsed.label, "and the two greens do not read the same")

-- A MENTION IS NOT A DEFINITION. `return loadChecklist(...)` appears in that
-- file; a text rung that counted it would be exactly the false ✓ this whole
-- tool exists to avoid, and the failure mode a pattern list falls into.
local mention = decide_one("web/print.ts:loadChecklist")
H.eq(mention.status, "missing", "a call is not a definition")
H.eq(mention.label, "✗ absent (no definition found)", "and says so in the text rung's own words")

-- An absent FILE is a file-level answer, not a definition-level one: there
-- was nothing to look inside.
local gone = decide_one("web/nope.ts:anything")
H.eq(gone.status, "missing", "a file that is not there is missing")
H.eq(gone.fidelity, "file", "at the file rung, because no definition was ever examined")

H.done("resolver_spec PASS")
