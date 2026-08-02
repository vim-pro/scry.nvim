-- Reach: what a feature enters by, and what that reaches.
--
-- The import graph's own behavior is pinned in imports_spec. What is
-- asserted here is scry's half: which members count as doors, whether an
-- answer is worth writing down, and whether writing it down actually shrinks
-- divergence. That last one is the only reason any of this exists.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local reach = require("scry.reach")
local mapmod = require("scry.map")

-- 1) EVERY MEMBER THAT NAMES A FILE IS A DOOR.
--
-- This took only `def` and `module` members — a vocabulary from before kinds
-- existed. On a map whose members are nine `route`s it meant a feature had
-- no doors at all: reach computed nothing, divergence never shrank, and the
-- failure looked like a resolver limitation rather than a filter.
local KINDS = {
  module = { probe = "file" },
  def = { probe = "definition" },
  route = { probe = "path", path = "src/pages/{name}.astro" },
  endpoint = { probe = "path", path = "src/pages/api/{name}.ts" },
}
local m = mapmod.parse({
  "feature someone can read a checklist",
  "  route [slug]",
  "  endpoint compile",
  "  module src/lib/db.js",
  "  def src/lib/run.js:start",
  "  never",
  "    console%.log",
  "  exercises",
  "    tests/read_spec.js:it reads",
}, KINDS)
local doors = reach.entry_points(m.features[1], KINDS)
H.eq(#doors, 4, "four doors: " .. table.concat(doors, ", "))
H.ok(vim.tbl_contains(doors, "src/pages/[slug].astro"), "a route is a door, and names an astro file")
H.ok(vim.tbl_contains(doors, "src/pages/api/compile.ts"), "so is an endpoint")
H.ok(vim.tbl_contains(doors, "src/lib/db.js"), "so is a module")
H.ok(vim.tbl_contains(doors, "src/lib/run.js"), "and a def enters by its file")

-- RELATIONS ARE NOT DOORS. A `never` names a pattern rather than a place,
-- and an `exercises` names the spec that CHECKS the feature rather than the
-- code that IS it — following that would pull the test suite into the
-- product's own footprint.
H.eq(vim.tbl_contains(doors, "tests/read_spec.js"), false, "an exercised spec is not part of the product")

-- A feature with no door reaches nothing, and that is an answer rather than
-- a failure — there was simply nothing to ask about.
local files, resolved = reach.of_feature(".", mapmod.parse({ "feature f", "  never", "    x" }).features[1])
H.eq(#files, 0, "a doorless feature reaches nothing")
H.eq(resolved, true, "and no question was left unanswered")

-- 2) THE CACHE STAMP COMPARES BY VALUE. runs.fingerprint returns a table, and
-- `~=` on two tables compares identities — so a cache guarded that way is
-- never valid, and the reach was computed, written, and then silently
-- ignored on every single read. Nothing errored; divergence just never
-- shrank.
local sf = vim.fn.tempname()
vim.fn.mkdir(sf, "p")
vim.fn.writefile({ "one" }, sf .. "/a.txt")
local stamp1 = reach.stamp(sf, { "a.txt" })
H.eq(type(stamp1), "string", "a stamp is a string, so it can be compared")
H.eq(reach.stamp(sf, { "a.txt" }), stamp1, "and is stable while the file is")
vim.fn.writefile({ "one", "two" }, sf .. "/a.txt")
H.ok(reach.stamp(sf, { "a.txt" }) ~= stamp1, "and changes when the file does")

-- A recorded reach goes stale with the files it was computed from. Keeping a
-- file out of the unclaimed list on an import that has since been deleted is
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

-- 3) DIVERGENCE SHRINKS, ON THE FILE TYPE THE OLD RESOLVERS COULD NOT READ.
--
-- This is what reach is for: a file a feature's entry points genuinely reach
-- is described by that feature, whether or not anyone listed it. Making
-- someone list it is what turned a map of a real project into eighty-six
-- hand-written members. The seed here is a .astro route, which no
-- stack-graphs grammar and no installed language server resolves — so under
-- either of them this test could not have been written at all.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/src/pages", "p")
vim.fn.mkdir(work .. "/src/lib", "p")
vim.fn.mkdir(work .. "/.scry", "p")
vim.fn.writefile({ '{"kinds":{"route":{"path":"src/pages/{name}.astro"}}}' }, work .. "/.scry/config.json")
vim.fn.writefile({
  "---",
  "import { all } from '../lib/db.js';",
  "---",
  "<ul>{all()}</ul>",
}, work .. "/src/pages/index.astro")
-- `.js` on the specifier, `.ts` on disk: the ESM convention whose chain
-- defeated the first resolver.
vim.fn.writefile(
  { "import { open } from './store.js';", "export function all() { return open() }" },
  work .. "/src/lib/db.ts"
)
vim.fn.writefile({ "export function open() { return [] }" }, work .. "/src/lib/store.ts")
vim.fn.writefile({ "export function nobody() {}" }, work .. "/src/lib/orphan.ts")

local kinds = mapmod.kinds_for(work)
local map_ = mapmod.parse({ "feature someone can read the index", "  route index" }, kinds)
-- The project's OWN config, not one built by hand: divergence resolves a
-- member to its file through the kinds in force, and a hand-made config has
-- none — so the route claimed nothing and its own file counted as unclaimed.
local config = require("scry.project").resolve(work)
local divergence = require("scry.divergence")

local before = select(1, divergence.unclaimed(work, map_, config))
H.eq(#before, 3, "three files nothing describes, before reach: " .. table.concat(before, ", "))

local reached, ok = reach.of_feature(work, map_.features[1], kinds)
H.eq(ok, true, "the route was readable")
H.ok(vim.tbl_contains(reached, "src/pages/index.astro"), "the seed is in its own footprint")
H.ok(vim.tbl_contains(reached, "src/lib/db.ts"), "one hop, through a .js specifier onto a .ts file")
H.ok(vim.tbl_contains(reached, "src/lib/store.ts"), "two hops: " .. table.concat(reached, ", "))
H.eq(vim.tbl_contains(reached, "src/lib/orphan.ts"), false, "and what nothing imports stays out")

local cache = reach.cache_load(work)
cache[map_.features[1].name] = { files = reached, at = 0, fingerprint = reach.stamp(work, reached) }
reach.cache_save(work, cache)

local after = select(1, divergence.unclaimed(work, map_, config))
H.eq(#after, 1, "one file left unclaimed, from one named route")
H.eq(after[1], "src/lib/orphan.ts", "and it is the one nothing reaches")

H.done("reach_spec PASS")
