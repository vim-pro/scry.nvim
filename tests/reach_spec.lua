-- Reach, now that the resolving lives in stackgraphs.nvim.
--
-- What is scry's here is narrow and worth being clear about: which files a
-- FEATURE enters by, whether an answer is good enough to write down, and
-- whether writing it down actually shrinks divergence. The engine's own
-- behavior — the output parser, the fidelity contract, the conventions — is
-- pinned in stackgraphs.nvim's specs, where it belongs. Asserting it twice
-- would mean scry's suite going red for a reason that is not scry's.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local reach = require("scry.reach")
local mapmod = require("scry.map")

-- 1) THE DEPENDENCY IS OPTIONAL, AND THE ABSENCE IS AN ANSWER. Without
-- stackgraphs.nvim every verdict scry gives still works — kinds are probed by
-- path and grep, `def` by treesitter — and only reach goes away. Erroring at
-- load would take a working tool off someone for a feature they may not use.
local sg = reach.sg()
if not sg then
  -- Loud, not silent: a green suite must never imply this ran.
  print("  (stackgraphs.nvim not on the runtimepath — reach NOT exercised)")
  H.ok(reach.status()[1]:find("not installed", 1, true) ~= nil, "and checkhealth says so plainly")
  H.done("reach_spec PASS (degraded)")
end

H.ok(#reach.status() > 0, "status names what is provisioned")

-- 2) WHAT A FEATURE ENTERS BY. This is the only part of reach that knows what
-- a feature is, and everything downstream is a question about paths. Only
-- defs and modules are entry points: a prohibition is not a door, and an
-- exercise names a command rather than a file.
local m = mapmod.parse({
  "feature someone can run a checklist",
  "  def src/lib/run.js:initChecklist",
  "  module src/pages/index.astro",
  "  def src/lib/run.js:finish",
  "  never",
  "    console%.log",
}, { module = true, def = true })
local seeds = reach.entry_points(m.features[1])
table.sort(seeds)
H.eq(#seeds, 2, "two doors, not three — one file named twice is one entry point")
H.eq(seeds[1], "src/lib/run.js", "a def enters by its file")
H.eq(seeds[2], "src/pages/index.astro", "and a module by itself")

-- A feature with no entry point reaches nothing, and that is a resolved
-- answer rather than a failure — there was simply nothing to ask about.
local empty
reach.of_feature(".", mapmod.parse({ "feature f", "  never", "    x" }).features[1], function(files, resolved)
  empty = { files = files, resolved = resolved }
end)
H.ok(H.wait(function()
  return empty ~= nil
end, 5000), "a doorless feature answers rather than hanging")
H.eq(#empty.files, 0, "with nothing")
H.eq(empty.resolved, true, "and no question was left unanswered")

-- 3) THE CACHE STAMP COMPARES BY VALUE. runs.fingerprint returns a table, and
-- `~=` on two tables compares identities — so a cache guarded that way is
-- never valid, and the reach was computed, written, and then silently ignored
-- on every single read. Nothing errored; divergence just never shrank.
local sf = vim.fn.tempname()
vim.fn.mkdir(sf, "p")
vim.fn.writefile({ "one" }, sf .. "/a.txt")
local stamp1 = reach.stamp(sf, { "a.txt" })
H.eq(type(stamp1), "string", "a stamp is a string, so it can be compared")
H.eq(reach.stamp(sf, { "a.txt" }), stamp1, "and is stable while the file is")
vim.fn.writefile({ "one", "two" }, sf .. "/a.txt")
H.ok(reach.stamp(sf, { "a.txt" }) ~= stamp1, "and changes when the file does")

-- A recorded reach goes stale with the files it was computed from. Keeping a
-- file out of the unclaimed list on a binding that has since been deleted is
-- the one failure a cache here can cause.
local cr = vim.fn.tempname()
vim.fn.mkdir(cr, "p")
vim.fn.writefile({ "x" }, cr .. "/reached.txt")
reach.cache_save(cr, {
  ["a feature"] = { files = { "reached.txt" }, at = 0, fingerprint = reach.stamp(cr, { "reached.txt" }) },
})
H.eq(#(reach.cached(cr, "a feature") or {}), 1, "a fresh record is used")
vim.fn.writefile({ "x", "y" }, cr .. "/reached.txt")
H.eq(reach.cached(cr, "a feature"), nil, "and a stale one is not")
H.eq(reach.cached(cr, "never recorded"), nil, "nor is a feature with no record")

-- 4) DIVERGENCE SHRINKS. This is what reach is for, and the only assertion
-- here that needs a real engine: a file a feature's entry points genuinely
-- reach is described by that feature, whether or not anyone listed it. Making
-- someone list it is what turned a map of a real project into eighty-six
-- hand-written members.
if sg.languages().typescript then
  local work = vim.fn.tempname()
  vim.fn.mkdir(work .. "/src", "p")
  vim.fn.writefile(
    { "import { helper } from './helper.ts';", "export function entry(id) { return helper(id); }" },
    work .. "/src/entry.ts"
  )
  vim.fn.writefile(
    { "import { deep } from './deep.ts';", "export function helper(x) { return deep(x); }" },
    work .. "/src/helper.ts"
  )
  vim.fn.writefile({ "export function deep(x) { return x; }" }, work .. "/src/deep.ts")
  vim.fn.writefile({ "export function unrelated() { return 0; }" }, work .. "/src/orphan.ts")

  local map_ = mapmod.parse({ "feature someone can run an entry", "  def src/entry.ts:entry" })
  local config = { sources = {}, map_path = ".scry/map.scry" }
  local divergence = require("scry.divergence")

  H.eq(#select(1, divergence.unclaimed(work, map_, config)), 3, "three files nothing describes, before reach")

  local ready
  sg.prepare(work, function()
    reach.of_feature(work, map_.features[1], function(files, resolved)
      vim.schedule(function()
        if resolved then
          local c = reach.cache_load(work)
          c[map_.features[1].name] = { files = files, at = 0, fingerprint = reach.stamp(work, files) }
          reach.cache_save(work, c)
        end
        ready = { files = files, resolved = resolved }
      end)
    end)
  end)
  H.ok(H.wait(function()
    return ready ~= nil
  end, 300000), "feature reach computed")
  H.eq(ready.resolved, true, "by an engine")

  -- Outbound, not inbound. Nothing CALLS entry — it is an entry point — so
  -- the references direction would answer zero here, which is why those are
  -- two different questions and not two names for one.
  H.ok(#ready.files >= 3, "the entry point reaches its dependencies: " .. table.concat(ready.files, ", "))

  local after = select(1, divergence.unclaimed(work, map_, config))
  H.eq(#after, 1, "one file left unclaimed, from one named entry point")
  H.eq(after[1], "src/orphan.ts", "and it is the one nothing reaches")

  -- 5) REACH IS COMPUTED FOR THE WHOLE MAP, not one feature at a time.
  --
  -- The cache divergence reads was only ever written by putting the cursor on
  -- a feature and running :ScryReach. So for anyone who did not know to make
  -- that per-feature gesture — which is everyone — the unclaimed count was
  -- computed as though reach did not exist. The command is gone and this runs
  -- in the background on every check.
  local whole = mapmod.parse({
    "feature someone can run an entry",
    "  def src/entry.ts:entry",
    "feature something else entirely",
    "  module src/orphan.ts",
  }, { module = true, def = true })

  local refreshed
  reach.refresh(work, whole, function(changed)
    refreshed = { changed = changed }
  end)
  H.ok(H.wait(function()
    return refreshed ~= nil
  end, 300000), "refresh answers for a whole map")
  H.eq(reach.progress.state, "done", "and says it is done")

  local cache = reach.cache_load(work)
  H.ok(cache["someone can run an entry"] ~= nil, "the feature with entry points is recorded")
  H.ok(#cache["someone can run an entry"].files >= 3, "with what it reaches")
  H.ok(cache["someone can run an entry"].fingerprint ~= nil, "and a fingerprint, so a stale answer is discarded")

  -- PROGRESS IS READABLE, because the header uses it to say whether the
  -- unclaimed count is an answer or an upper bound.
  H.ok(reach.progress.state ~= "off", "progress is legible to the header")
else
  print("  (no typescript engine provisioned — divergence-shrink NOT exercised)")
end

H.done("reach_spec PASS")
