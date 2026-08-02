-- The map parser: lossless round-trips, claim extraction, stamps, and the
-- rule that there are no parse errors — only claims and prose.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")

local SRC = {
  "feature providers",
  "",
  "  The provider layer turns a Request into text and calls back once",
  "  on the main loop. Transport only: no UI, no lists.",
  "",
  "  contains",
  "    lua/conjurer/providers/cli.lua:request  -- @michael 2026-07-26 3f9a01",
  "    lua/conjurer/providers/known.lua:resolve_api",
  "  calls",
  "    known.lua::resolve_api",
  "  never",
  "    vim\\.ui\\.",
  "",
  "some stray prose at feature level",
  "",
  "feature empty feature",
  "  just prose here, no claims",
}

-- 1) byte-identical round trip
local m = map.parse(vim.deepcopy(SRC))
local out = map.serialize(m)
H.eq(#out, #SRC, "line count preserved")
for i = 1, #SRC do
  H.eq(out[i], SRC[i], "line " .. i .. " byte-identical")
end

-- 2) structure
H.eq(#m.features, 2, "two features")
H.eq(m.features[1].name, "providers", "feature name")
-- A feature declares no globs. Its footprint is DERIVED from the files its
-- claims name, so the map cannot claim ground it has said nothing about.
local fp = map.footprint(m.features[1])
H.eq(#fp, 2, "footprint is the two files the contains-claims name")
H.eq(fp[1], "lua/conjurer/providers/cli.lua", "in order of first appearance")
H.eq(#map.footprint(m.features[2]), 0, "a prose-only feature locates nothing")
H.eq(#m.claims, 4, "four claims total")
H.eq(#m.features[2].claims, 0, "prose-only feature has no claims")

-- 3) claim details
local c1, c2, c3, c4 = m.claims[1], m.claims[2], m.claims[3], m.claims[4]
H.eq(c1.kind, "def", "claim 1 kind")
H.eq(c1.target, "lua/conjurer/providers/cli.lua:request", "stamped claim target excludes the stamp")
H.eq(c1.stamp.user, "michael", "stamp user (without @)")
H.eq(c1.stamp.date, "2026-07-26", "stamp date")
H.eq(c1.stamp.hash, "3f9a01", "stamp hash")
H.eq(c2.stamp, nil, "unstamped claim")
H.eq(c3.kind, "calls", "calls section")
H.eq(c4.kind, "never", "never section")
H.eq(c4.target, "vim\\.ui\\.", "never target is the verbatim pattern")
H.eq(c4.feature, "providers", "claims know their feature")

-- 4) a DEDENTED line ends a section, and a blank one does not. The blank
-- line after the never-pattern reads like a terminator to a human; treating
-- it as one would silently demote every claim after it to prose, and for a
-- never-block route a prohibition into the repo. Indentation is the grammar.
H.eq(m.claims[#m.claims].target, "vim\\.ui\\.", "stray prose never became a claim")

-- 5) no parse errors on garbage — everything unrecognized is prose, and a
-- dedented line ENDS its section (claims after it are prose until the next
-- section header).
local weird = map.parse({
  "?????",
  "   ",
  "feature c",
  "  contains",
  "    real.lua:sym",
  "not-indented-enough",
  "    looks-like-a-claim-but-is-prose",
})
H.eq(#weird.claims, 1, "claim before the dedent parsed; line after it is prose")
H.eq(weird.claims[1].target, "real.lua:sym", "the real claim survived its weird neighbors")

-- Ownership is inferred, never performed: the provenance trail is keyed to
-- a hash of the claim's text, so EDITING a claim voids its trail — the old
-- ratification property, kept without the stamp.
local prov = require("scry.provenance")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local m2 = map.parse({ "feature a", "  contains", "    x.lua:one" })
local claim = m2.claims[1]
H.eq(prov.owned(root, claim), false, "an untouched claim is not owned")
prov.record(root, claim, "authored")
H.eq(prov.owned(root, claim), true, "authoring is ownership")
claim = { kind = claim.kind, target = "x.lua:two", feature = claim.feature, lnum = claim.lnum }
H.eq(prov.owned(root, claim), false, "an edited claim's trail is void")
prov.record(root, claim, "conjured")
H.eq(prov.owned(root, claim), false, "conjuring alone is not ownership")
prov.record(root, claim, "green")
H.eq(prov.owned(root, claim), true, "conjured and came true is ownership")
-- stamps from the ratification era still PARSE (legacy lines are claims with
-- a stamp field), they just no longer mean anything
local legacy = map.parse({ "feature a", "  contains", "    x.lua:one  -- @w0zro 2026-07-26 abc123" })
H.eq(legacy.claims[1].target, "x.lua:one", "legacy stamped claim still parses to its target")
H.eq(legacy.claims[1].stamp.user, "w0zro", "and keeps its stamp as data")

H.done("map_spec PASS")

-- A `contains` target with no symbol names the FILE. This exists because
-- divergence is file-level while footprints are symbol-derived: a file that
-- defines nothing could be reported unclaimed with no way to claim it, and an
-- accusation you cannot act on is a bug in the report.
local file_level = map.parse({
  "feature bootstrap",
  "  contains",
  "    plugin/scry.lua",
  "    lua/scry/init.lua:setup",
})
H.eq(#file_level.claims, 2, "a bare path is a claim, not prose")
H.eq(map.claim_path(file_level.claims[1]), "plugin/scry.lua", "and it locates the file itself")
H.eq(map.claim_path(file_level.claims[2]), "lua/scry/init.lua", "alongside the symbol form")
H.eq(#map.footprint(file_level.features[1]), 2, "both reach the footprint")
H.eq(
  table.concat(map.serialize(file_level), "\n"),
  "feature bootstrap\n  contains\n    plugin/scry.lua\n    lua/scry/init.lua:setup",
  "and it round-trips"
)
