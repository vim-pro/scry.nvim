-- What would make these answers better, said without being asked.
--
-- Scry knows its own ceiling exactly: which claims stopped at the text rung
-- because no grammar is installed, that `✓ done` is unreachable here because
-- nothing has been run. It knew all of it and said none of it unless someone
-- happened to run `:checkhealth`. A tool that silently underperforms and
-- waits to be interrogated will underperform forever.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local advice = require("scry.advice")
local mapmod = require("scry.map")

-- WITHOUT CONJURER, NOTHING ELSE MATTERS — `~`, `+` and `:Scry {intent}` all
-- do nothing, which is most of the reason this buffer exists. It outranks
-- every other suggestion, and this suite does not have it on the runtimepath,
-- so assert that first and then stand it up for the rest.
local bare = mapmod.parse({ "feature f", "  def web/a.ts:one" })
local without = advice.best(bare, { at = 0, verdicts = {} }, {})
H.eq(without.id, "conjurer", "a missing operator outranks everything else")
package.loaded["conjurer"] = package.loaded["conjurer"] or { config = {} }

local function report_for(map_, fidelity)
  local verdicts = {}
  for _, c in ipairs(map_.claims) do
    verdicts[mapmod.claim_id(c)] = { status = "backed", fidelity = fidelity, label = "x" }
  end
  return { at = os.time(), verdicts = verdicts }
end

-- 1) IT COUNTS FROM YOUR OWN MAP. A suggestion that does not name a number
-- from the claims in front of you is a suggestion you learn to skip.
local capped = mapmod.parse({
  "feature f",
  "  def web/print.ts:renderPrintSheet",
  "  def web/site.ts:canonicalUrl",
  "  def web/page.astro:Layout",
})
local best = advice.best(capped, report_for(capped, "text-def"), {})
H.eq(best.id, "grammar", "claims capped at the text rung are the top suggestion")
H.ok(best.say:find("3 claim", 1, true) ~= nil, "counted, not described: " .. best.say)
H.ok(best.say:find("typescript", 1, true) ~= nil, "and it names the grammar, from the extensions in the map")
H.ok(best.say:find("astro", 1, true) ~= nil, "every one of them")
H.ok(best.how:find("TSInstall", 1, true) ~= nil, "with something to run: " .. best.how)

-- IT ONLY NAMES GRAMMARS THAT EXIST. A suggestion to install a parser for a
-- language nobody wrote one for is worse than silence.
local odd = mapmod.parse({ "feature f", "  def notes/thing.xyzzy:whatever" })
local none = advice.best(odd, report_for(odd, "text-def"), {})
H.ok(none == nil or none.id ~= "grammar", "an extension with no known grammar suggests nothing about grammars")

-- 2) NOTHING RAN. `✓ done` is the only state that means "works" and it costs
-- an execution, so a map with no exercised claim has a ceiling it will never
-- reach — and nothing on the page said so.
local structural = mapmod.parse({ "feature f", "  def lua/a.lua:one" })
local run = advice.best(structural, report_for(structural, "ts-def"), {})
H.eq(run.id, "exercises", "a map that has never been run is told so")
H.ok(run.say:find("done", 1, true) ~= nil, "and told what it costs: " .. run.say)

-- An exercised claim with nowhere to run is a different problem, and a
-- heavier one: the claim exists and cannot ever answer.
local unrunnable = mapmod.parse({ "feature f", "  exercises", "    tests/a_spec.lua" })
local cmd = advice.best(unrunnable, report_for(unrunnable, "run"), {})
H.eq(cmd.id, "test-cmd", "an exercised claim with no test command is flagged")
H.ok(cmd.how:find("test", 1, true) ~= nil, "with the setting to set: " .. cmd.how)
-- ...and configured, there is nothing left to say about it.
local ok_cfg = advice.best(unrunnable, report_for(unrunnable, "run"), { test = { cmd = { "make" } } })
H.ok(ok_cfg == nil or ok_cfg.id ~= "test-cmd", "a configured command is not nagged about")

-- 3) ONE THING AT A TIME, ranked by what it buys HERE. A list of five is a
-- list nobody reads, and the second-best is noise until the best is done.
local both = mapmod.parse({
  "feature f",
  "  def web/a.ts:one",
  "  def web/b.ts:two",
  "  def web/c.ts:three",
})
local top = advice.best(both, report_for(both, "text-def"), {})
H.eq(top.id, "grammar", "three capped claims outrank `nothing has run`")
H.eq(type(top.say), "string", "and there is exactly one of them")

-- 4) SAID ONCE PER PROJECT. The ceiling does not move while you work, and a
-- message that repeats on every check is a message you configure away —
-- which loses the one time it mattered.
advice.reset()
local said = {}
local real = vim.notify
vim.notify = function(msg)
  said[#said + 1] = msg
end
advice.offer("/proj", capped, report_for(capped, "text-def"), {})
advice.offer("/proj", capped, report_for(capped, "text-def"), {})
advice.offer("/other", capped, report_for(capped, "text-def"), {})
vim.notify = real
H.eq(#said, 2, "twice for two projects, not four times for four checks")
H.ok(said[1]:find("scry", 1, true) ~= nil, "and it says who is talking")

-- 5) NOTHING TO SAY IS SAID AS NOTHING. A map with no shortfall gets no
-- message at all, or the mechanism becomes noise on exactly the projects
-- that got everything right.
advice.reset()
local healthy = mapmod.parse({ "feature f", "  exercises", "    tests/a_spec.lua" })
H.eq(
  advice.best(healthy, report_for(healthy, "run"), { test = { cmd = { "make" } } }),
  nil,
  "a project that is not limited by anything hears nothing"
)

-- 6) CRUCIAL IS NOT ADVICE. Without ripgrep every prohibition, reference and
-- divergence check errors and the glass fills with `– resolver error`, which
-- reads as a broken project rather than a missing tool. A `never` that has
-- silently stopped being checked is the most dangerous state here, so this is
-- a refusal rather than a suggestion — and it is answered before anything
-- opens.
local missing, how = advice.crucial()
if vim.fn.executable("rg") == 1 then
  H.eq(missing, nil, "with ripgrep on PATH there is nothing crucial missing")
else
  H.ok(missing:find("ripgrep", 1, true) ~= nil, "without it, it is named")
  H.ok(how ~= nil and #how > 0, "and so is the way to get it")
end

H.done("advice_spec PASS")
