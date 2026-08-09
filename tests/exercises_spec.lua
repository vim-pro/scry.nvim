-- The second evidence axis: a claim backed by running something.
--
-- The load-bearing assertions here are the two that keep dynamic evidence
-- honest — that CHECKING never executes anything, and that a pass recorded
-- before the code moved is not reported as a pass.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local runs = require("scry.runs")
local run = require("scry.run")
local resolver = require("scry.resolvers.ts_rg")

-- A workspace with one source file and two specs: one that passes, one that
-- fails. Real processes, real exit codes — the point is the wiring.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
vim.fn.mkdir(work .. "/tests", "p")
vim.fn.writefile({ "local M = {}", "function M.add(a, b)", "  return a + b", "end", "return M" }, work .. "/lua/calc.lua")
vim.fn.writefile({ "os.exit(0)" }, work .. "/tests/green_spec.lua")
vim.fn.writefile({ 'io.stderr:write("FAIL: add is wrong\\n")', "os.exit(1)" }, work .. "/tests/red_spec.lua")

local SRC = {
  "feature calc",
  "",
  "  exercises",
  "    tests/green_spec.lua",
  "    tests/red_spec.lua",
  "    tests/missing_spec.lua",
}
local m = map.parse(SRC)

-- 1) the kind parses, and a blank line before the section doesn't eat it
H.eq(#m.claims, 3, "three exercises claims parsed")
H.eq(m.claims[1].kind, "exercises", "kind is exercises")
H.eq(m.claims[1].target, "tests/green_spec.lua", "target is the spec path")

local ctx = { root = work, globs = { "lua/*.lua" } }
local function verdict_for(target)
  local v
  resolver.check_exercises(ctx, { kind = "exercises", target = target, feature = "calc" }, function(res)
    v = res
  end)
  H.ok(H.wait(function()
    return v ~= nil
  end, 5000), "verdict settled for " .. target)
  return v
end

-- 2) a spec that was never run is UNCHECKED, not failing. "Nobody ran this"
-- and "this is broken" are different facts and must not share a column.
local v = verdict_for("tests/green_spec.lua")
H.eq(v.status, "unchecked", "an unrun spec is unchecked")
H.ok(v.label:find("unrun", 1, true) ~= nil, "and says so: " .. v.label)

-- 3) CHECKING NEVER EXECUTES. Point the config at a command that leaves a
-- marker on disk, check every claim, and assert the marker never appears.
-- A resolver that quietly shelled out would pass every other test in this
-- file and turn :Scry into something that runs your suite on every render.
local marker = work .. "/EXECUTED"
require("scry").setup({ test = { cmd = { "sh", "-c", "touch " .. marker .. "; exit 0" } } })
local report
require("scry.check").run(m, { root = work, resolver = resolver }, function(r)
  report = r
end)
H.ok(H.wait(function()
  return report ~= nil
end, 8000), "check settled")
H.eq(vim.loop.fs_stat(marker), nil, "checking did NOT run the test command")

-- 4) a missing spec file is absent, not unrun — the claim points at nothing
H.eq(report.verdicts[map.claim_id(m.claims[3])].status, "missing", "a nonexistent spec is absent")

-- 5) run for real, then the verdicts turn hard
require("scry").setup({ test = { cmd = { "nvim", "--headless", "-u", "NONE", "-l" } } })
local function deps_for(spec)
  local d = runs.scope(work, { "lua/*.lua" })
  d[#d + 1] = spec
  return d
end
local done = 0
run.one(work, "tests/green_spec.lua", require("scry").config, deps_for("tests/green_spec.lua"), function()
  done = done + 1
end)
run.one(work, "tests/red_spec.lua", require("scry").config, deps_for("tests/red_spec.lua"), function()
  done = done + 1
end)
H.ok(H.wait(function()
  return done == 2
end, 20000), "both specs ran")

v = verdict_for("tests/green_spec.lua")
H.eq(v.status, "backed", "the passing spec backs its claim")
H.eq(v.fidelity, "run", "fidelity records that this came from a run, not a read")
H.ok(v.label:find("ago", 1, true) ~= nil, "and the label carries the age: " .. v.label)

v = verdict_for("tests/red_spec.lua")
H.eq(v.status, "violated", "the failing spec breaks its claim")
H.ok(#(v.evidence or {}) > 0, "with the failure output as evidence")
H.ok(
  table.concat(vim.tbl_map(function(e)
    return e.text
  end, v.evidence), " "):find("add is wrong", 1, true) ~= nil,
  "the reason travels with the verdict"
)

-- 6) STALENESS. Touch a file in the feature's scope and the pass stops being
-- reported as a pass. This is the failure mode that matters: a green verdict
-- from before your last edit looks like the strongest thing scry renders.
vim.fn.writefile({ "local M = {}", "-- edited", "return M" }, work .. "/lua/calc.lua")
v = verdict_for("tests/green_spec.lua")
H.eq(v.status, "unchecked", "a pass from before the edit is no longer a pass")
H.ok(v.label:find("stale", 1, true) ~= nil, "and names the reason: " .. v.label)

-- ...and it lands in the unchecked column rather than vanishing from the count
local d = require("scry.header").count(map.parse({ "feature calc", "  contains", "    lua/calc.lua:add", "  exercises", "    tests/green_spec.lua" }), nil)
H.eq(d.unchecked, 2, "unrun/stale claims are counted, not omitted")
H.eq(d.backed + d.missing + d.violated + d.unchecked, d.claims, "the columns still account for everything")

-- 7) a labeled assertion must exist in the spec's source
vim.fn.writefile({ 'local x = "adds two numbers"', "os.exit(0)" }, work .. "/tests/green_spec.lua")
local relabelled = false
run.one(work, "tests/green_spec.lua", require("scry").config, deps_for("tests/green_spec.lua"), function()
  relabelled = true
end)
H.ok(H.wait(function()
  return relabelled
end, 20000), "re-ran the relabelled spec")

v = verdict_for("tests/green_spec.lua:adds two numbers")
H.eq(v.status, "backed", "a label present in the spec is accepted")
H.ok(v.label:find("assertion present", 1, true) ~= nil, "and is labeled weakly, on purpose: " .. v.label)

v = verdict_for("tests/green_spec.lua:handles negative numbers")
H.eq(v.status, "missing", "a label the spec never mentions is absent")
H.ok(v.label:find("no assertion", 1, true) ~= nil, "named precisely: " .. v.label)

-- 8) run.specs dedupes: two claims on one file are one execution
local m2 = map.parse({
  "feature calc",
  "  exercises",
  "    tests/green_spec.lua:one",
  "    tests/green_spec.lua:two",
  "    tests/red_spec.lua",
})
H.eq(#run.specs(m2), 2, "two distinct spec files, not three runs")
H.eq(#run.specs(m2, "nope"), 0, "and a feature filter narrows it")

-- 9) THE VACUITY GATE. A spec written before the code must fail; one that
-- passes while nothing it should exercise exists is asserting nothing. The
-- run itself cannot tell you this — the process exits 0 either way — so the
-- check has to notice it across claims.
local vac = vim.fn.tempname()
vim.fn.mkdir(vac .. "/lua", "p")
vim.fn.mkdir(vac .. "/tests", "p")
vim.fn.writefile({ "os.exit(0)" }, vac .. "/tests/eager_spec.lua")
vim.fn.writefile({ "local M = {}", "return M" }, vac .. "/lua/thing.lua")
local mv = map.parse({
  "feature unbuilt",
  "  contains",
  "    lua/thing.lua:not_written_yet",
  "  exercises",
  "    tests/eager_spec.lua",
})
require("scry").setup({ test = { cmd = { "nvim", "--headless", "-u", "NONE", "-l" } } })
-- The run must record everything a later check will ask about: an
-- unrecorded dependency counts as changed, which is what run.start does.
local function vac_deps()
  local d = runs.scope(vac, { "lua/*.lua" })
  d[#d + 1] = "tests/eager_spec.lua"
  return d
end
local ran = false
run.one(vac, "tests/eager_spec.lua", require("scry").config, vac_deps(), function()
  ran = true
end)
H.ok(H.wait(function()
  return ran
end, 20000), "the eager spec ran green")

local rv
require("scry.check").run(mv, { root = vac, resolver = resolver }, function(r)
  rv = r
end)
H.ok(H.wait(function()
  return rv ~= nil
end, 10000), "checked")
local gated = rv.verdicts[map.claim_id(mv.claims[2])]
H.eq(gated.status, "unchecked", "a green spec over an unbuilt feature is not a pass")
H.ok(gated.label:find("vacuous", 1, true) ~= nil, "and is named as such: " .. gated.label)

-- ...and the gate stays quiet once the feature is actually built. A
-- half-finished feature has plenty for a spec to legitimately exercise; a
-- false "vacuous" would teach you to ignore the real one.
vim.fn.writefile({ "local M = {}", "function M.not_written_yet() end", "return M" }, vac .. "/lua/thing.lua")
run.one(vac, "tests/eager_spec.lua", require("scry").config, vac_deps(), function() end)
H.wait(function()
  return false
end, 1500)
local rv2
require("scry.check").run(mv, { root = vac, resolver = resolver }, function(r)
  rv2 = r
end)
H.ok(H.wait(function()
  return rv2 ~= nil
end, 10000), "re-checked")
H.eq(rv2.verdicts[map.claim_id(mv.claims[1])].status, "backed", "the definition landed")
H.eq(rv2.verdicts[map.claim_id(mv.claims[2])].status, "backed", "so the spec counts as a pass again")

H.done("exercises_spec PASS")
