-- Reflexion fan-out with a fake resolver (recorded {claim, cb}, answered by
-- hand — conjurer's aggregate_spec pattern), plus debt arithmetic.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local check = require("scry.check")
local debt = require("scry.debt")

local SRC = {
  "# a",
  "  files lua/*.lua",
  "  contains",
  "    x.lua:one  -- @w0zro 2026-07-26 " .. require("scry.ratify").hash("x.lua:one"),
  "    x.lua:two",
  "  never",
  "    bad_pattern",
}
local m = map.parse(SRC)

-- fake resolver records calls; the spec answers them
local calls = {}
local fake = {
  name = "fake",
  check_contains = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
  check_never = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
  check_calls = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
}

local report
check.run(m, { root = "/nowhere", resolver = fake }, function(r)
  report = r
end)
H.eq(#calls, 3, "one resolver call per claim")
H.eq(report, nil, "report not settled until every verdict arrives")
H.eq(calls[1].globs[1], "lua/*.lua", "concern globs travel in ctx")

calls[1].cb({ status = "backed", fidelity = "ts-def", label = "✓ defined" })
calls[2].cb({ status = "missing", fidelity = "ts-def", label = "✗ absent" })
H.eq(report, nil, "still pending")
calls[3].cb({ status = "violated", fidelity = "rg-text", label = "✗ VIOLATED", evidence = {} })
H.ok(report ~= nil, "settled once, after the last verdict")
H.ok(report.at > 0, "report is timestamped")

-- debt: claim 1 ratified+backed; claim 2 unratified+missing; claim 3
-- unratified+violated → counted once per axis
local d = debt.count(m, report)
H.eq(d.claims, 3, "claim count")
H.eq(d.backed, 1, "backed")
H.eq(d.missing, 1, "missing")
H.eq(d.violated, 1, "violated")
H.eq(d.unratified, 2, "unratified counts both stampless claims")

-- header renders separate numbers with the claim count leading
local header = debt.header(d, report.at)
H.ok(header:find("3 claims", 1, true) ~= nil, "claim count leads")
H.ok(header:find("1 backed", 1, true) ~= nil, "backed shown")
H.ok(header:find("1 violated", 1, true) ~= nil, "violated shown")
H.ok(header:find("files on disk", 1, true) ~= nil, "the disk caveat travels with every render")

-- A claim no engine could answer must occupy a column of its own. The
-- reader's whole interaction with debt is glancing at this line: if unchecked
-- claims are simply absent from it, "0 missing · 0 violated" reads as a clean
-- bill of health for claims nothing ever looked at.
local SRC2 = {
  "# mixed",
  "  files src/*",
  "  contains",
  "    src/app.lua:go",
  "    src/thing.py:handle", -- no lua resolver
  "    src/other.rb:run", -- no lua resolver
}
local m2 = map.parse(SRC2)
calls = {}
local report2
check.run(m2, { root = "/nowhere", resolver = fake }, function(r)
  report2 = r
end)
calls[1].cb({ status = "backed", fidelity = "ts-def", label = "✓ defined" })
calls[2].cb({ status = "unchecked", fidelity = "none", label = "– unchecked (no lua resolver)" })
calls[3].cb({ status = "error", fidelity = "none", label = "– resolver error" })

local d2 = debt.count(m2, report2)
H.eq(d2.unchecked, 2, "unchecked and error verdicts both land in the unchecked column")
H.eq(d2.backed + d2.missing + d2.violated + d2.unchecked, d2.claims, "the four columns account for every claim")
local h2 = debt.header(d2, report2.at)
H.ok(h2:find("2 unchecked", 1, true) ~= nil, "the header names them: " .. h2)
H.ok(debt.header(d, report.at):find("unchecked", 1, true) == nil, "and stays quiet when there are none")

-- No report at all is not a pass either: every claim is unchecked.
local d3 = debt.count(m2, nil)
H.eq(d3.unchecked, 3, "with no report, nothing is accounted for")
H.eq(d3.backed, 0, "and nothing is backed")

-- empty map settles immediately
local settled = false
check.run(map.parse({}), { root = "/nowhere", resolver = fake }, function()
  settled = true
end)
H.eq(settled, true, "empty map settles synchronously")

H.done("check_spec PASS")
