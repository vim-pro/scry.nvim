-- Reach: what actually binds to a definition, as against what merely
-- mentions its name. The engine is what tells those apart, and every
-- assertion here is about not confusing them.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local reach = require("scry.reach")

-- 1) LANGUAGES scry can resolve, and the honest nil for the rest.
H.eq(reach.lang_of("src/lib/run.js"), "javascript", "js")
H.eq(reach.lang_of("src/pages/api/compile.ts"), "typescript", "ts")
H.eq(reach.lang_of("src/App.tsx"), "tsx", "tsx")
H.eq(reach.lang_of("lua/scry/map.lua"), nil, "lua has no stack-graphs engine, and saying so is the point")
H.eq(reach.engine("lua"), nil, "so no binary is claimed for it")
H.eq(reach.engine(nil), nil, "nor for a file with no language")

-- 2) THE OUTPUT PARSER, against bytes the engine really produced. It was
-- written from the archived vim.pro's parser first, and that parser read
-- NOTHING here: the marker is `has N definitions`, not `has definitions:`.
-- A silent zero is the worst failure this module has, so the format is
-- pinned to a real transcript rather than to a description of one.
local ROOT = "/tmp/proj"
local REAL = table.concat({
  ROOT .. "/src/page.ts:2:11: found 2 definitions for 1 references",
  "queried reference",
  ROOT .. "/src/page.ts:2:11:",
  '2 | const x = initChecklist("a");',
  "  |           ^^^^^^^^^^^^^",
  "",
  "has 2 definitions",
  ROOT .. "/src/page.ts:1:10:",
  "1 | import { initChecklist } from './lib.ts';",
  ROOT .. "/src/lib.ts:1:17:",
  "1 | export function initChecklist(id: string) {",
}, "\n")

local defs = reach.parse_query(REAL, ROOT)
local at = defs["src/page.ts:2:11"]
H.ok(at ~= nil, "the queried position is keyed relative to the root")
H.eq(#at, 2, "both definitions are read")
H.eq(at[2].path, "src/lib.ts", "absolute paths come back relative")
H.eq(at[2].lnum, 1, "with their line")

-- The reference is echoed with its own position BEFORE the marker. Reading
-- locations without waiting for `has N definitions` would file a reference
-- as its own definition — which resolves everything to itself and reports
-- perfect reach for a symbol nothing uses.
for _, d in ipairs(at) do
  H.eq(d.path == "src/page.ts" and d.lnum == 2, false, "the echoed reference is not counted as a definition")
end

-- `has no definitions` must not leave the collector open, or the NEXT
-- position's echo lands in this one's list.
local none = reach.parse_query(
  table.concat({
    ROOT .. "/a.ts:1:1: found 0 definitions for 2 references",
    "has no definitions",
    ROOT .. "/b.ts:9:9:",
  }, "\n"),
  ROOT
)
H.eq(#(none["a.ts:1:1"] or {}), 0, "nothing is collected after `has no definitions`")

-- THE PATH THE ENGINE PRINTS IS THE REAL ONE. On macOS /var is a symlink to
-- /private/var, so a root of /var/folders/…/proj comes back as
-- /private/var/folders/…/proj. Stripping only the root as given leaves every
-- path absolute, every comparison fails, and reach reports ZERO for a symbol
-- with references — a silent wrong answer, which is the failure mode this
-- module is entirely about avoiding.
local symlinked = reach.parse_query(
  table.concat({
    "/private/var/x/src/page.ts:2:11: found 1 definitions for 1 references",
    "has 1 definitions",
    "/private/var/x/src/lib.ts:1:17:",
  }, "\n"),
  "/var/x",
  "/private/var/x"
)
H.ok(symlinked["src/page.ts:2:11"] ~= nil, "the real path is stripped too")
H.eq(symlinked["src/page.ts:2:11"][1].path, "src/lib.ts", "so a definition is comparable")

-- 3) THE FILTER. A candidate survives only if the engine put a definition
-- at the target's own location — never because its name matched.
local cands = {
  { path = "src/page.ts", lnum = 2, col = 11 },
  { path = "src/decoy.ts", lnum = 2, col = 11 },
}
local kept = reach.keep_bound(cands, { path = "src/lib.ts", lnum = 1 }, defs)
H.eq(#kept, 1, "only the bound candidate survives")
H.eq(kept[1].path, "src/page.ts", "and it is the right one")

local wrong = reach.keep_bound(cands, { path = "src/other.ts", lnum = 1 }, defs)
H.eq(#wrong, 0, "a candidate bound to a DIFFERENT definition is not reach")

-- 4) STATUS is readable whether or not anything is provisioned, because
-- "not provisioned" is a thing a reader needs to be told.
local status = reach.status()
H.ok(#status > 0, "status names the engines")
local joined = table.concat(status, "\n")
H.ok(
  joined:find("provisioned", 1, true) ~= nil,
  "and says of each whether it is there: " .. joined:sub(1, 80)
)

-- 5) END TO END, only where an engine actually exists. Skipped loudly
-- rather than silently, so a green suite never implies this ran.
if reach.engine("typescript") then
  local work = vim.fn.tempname()
  vim.fn.mkdir(work .. "/src", "p")
  vim.fn.writefile({ "export function target(id) {", "  return id;", "}" }, work .. "/src/lib.ts")
  vim.fn.writefile({ "import { target } from './lib.ts';", 'const x = target("a");' }, work .. "/src/page.ts")
  -- a different function with the same name: what text search cannot tell apart
  vim.fn.writefile({ "function target(x) { return x; }", "const y = target(2);" }, work .. "/src/decoy.ts")

  local indexed
  reach.index(work, "typescript", { "src/lib.ts", "src/page.ts", "src/decoy.ts" }, function(ok)
    indexed = ok
  end)
  H.ok(H.wait(function()
    return indexed ~= nil
  end, 120000), "indexing finished")

  local got
  reach.callers(work, { path = "src/lib.ts", lnum = 1, name = "target" }, function(r)
    got = r
  end)
  H.ok(H.wait(function()
    return got ~= nil
  end, 120000), "reach computed")
  H.eq(got.resolved, true, "an engine answered")
  H.eq(got.n, 1, "one real reference, not the four a name match finds")
  H.eq(got.hits[1].path, "src/page.ts", "and the decoy's own call is not reach")
else
  print("  (no typescript engine provisioned — end-to-end reach NOT exercised)")
end

-- 6) THE CACHE STAMP compares by VALUE. runs.fingerprint returns a table,
-- and `~=` on two tables compares identities — so a cache guarded that way
-- is never valid, and the reach was computed, written, and then silently
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

-- 7) DIVERGENCE SHRINKS. This is what reach is for: a file an entry point
-- genuinely reaches is described by that feature, whether or not anyone
-- listed it. Making someone list it is what turned a map of a real project
-- into eighty-six hand-written members.
if reach.engine("typescript") then
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

  local map_ = require("scry.map").parse({ "feature someone can run an entry", "  def src/entry.ts:entry" })
  local config = { sources = {}, map_path = ".scry/map.scry" }
  local divergence = require("scry.divergence")

  local before = select(1, divergence.unclaimed(work, map_, config))
  H.eq(#before, 3, "three files nothing describes, before reach")

  local ready
  reach.with_index(work, "typescript", function()
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
  -- the callers direction would answer zero here, which is why these are
  -- two different questions and not two names for one.
  H.ok(#ready.files >= 3, "the entry point reaches its transitive dependencies: " .. table.concat(ready.files, ", "))

  local after = select(1, divergence.unclaimed(work, map_, config))
  H.eq(#after, 1, "one file left unclaimed, from one named entry point")
  H.eq(after[1], "src/orphan.ts", "and it is the one nothing reaches")
else
  print("  (no typescript engine — divergence-shrink NOT exercised)")
end

H.done("reach_spec PASS")
