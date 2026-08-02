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
  reach.of(work, { path = "src/lib.ts", lnum = 1, name = "target" }, function(r)
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

H.done("reach_spec PASS")
