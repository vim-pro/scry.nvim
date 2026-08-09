-- The map parser: lossless round-trips, claim extraction, and the rule that
-- there are no parse errors — only claims and prose.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")

local SRC = {
  "feature providers",
  "",
  "  The provider layer turns a Request into text and calls back once",
  "  on the main loop. Transport only: no UI, no lists.",
  "",
  "  contains",
  "    lua/conjurer/providers/cli.lua:request",
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
H.eq(c1.target, "lua/conjurer/providers/cli.lua:request", "claim target")
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

-- A FEATURE IS NAMED ONCE; ITS MEMBERS ACCUMULATE. Writing the name again
-- re-opens it rather than starting a second feature with the same name.
--
-- The lookup was already inconsistent: map.claims held both blocks' claims
-- while map.features held two entries and M.feature(name) returned only the
-- first, so every by-name caller saw half a feature.
--
-- And it is the move a drafting pass did not have. A batch whose files serve
-- a feature already in the map had no way to say so — its only legal output
-- was a NEW feature — so it invented one, and the map fragmented a file at a
-- time: 301 features over 60 files on a real run.
local reopened = map.parse({
  "feature someone can read a checklist",
  "  contains",
  "    src/a.lua",
  "",
  "Prose between the blocks, which is still prose.",
  "",
  "feature someone can read a checklist",
  "  contains",
  "    src/b.lua",
})
H.eq(#reopened.features, 1, "one feature, not two of the same name")
H.eq(#reopened.features[1].claims, 2, "carrying both blocks' members")
H.eq(#reopened.claims, 2, "and the flat claim list agrees, as it always did")
H.eq(#map.feature(reopened, "someone can read a checklist").claims, 2, "a by-name lookup sees all of it")

-- Every line it is opened on is recorded, because the glass puts a verdict
-- beside each one and a header with nothing next to it reads as unchecked.
H.eq(#reopened.features[1].lnums, 2, "both header lines are known")
H.eq(reopened.features[1].lnums[1], 1, "the first")
H.eq(reopened.features[1].lnums[2], 7, "and the one that re-opened it")
H.eq(reopened.features[1].lnum, 1, "and `lnum` still means the first, as before")

-- A different name is still a different feature. Merging is by exact name;
-- deciding two wordings mean the same thing is the reader's call, not ours.
local distinct = map.parse({
  "feature someone can read a checklist",
  "  contains",
  "    src/a.lua",
  "feature someone can read a checklist, quickly",
  "  contains",
  "    src/b.lua",
})
H.eq(#distinct.features, 2, "near-identical wording is two features")

-- And the text is untouched: serialization is the stored lines, so a map
-- that re-opens a feature round-trips byte for byte like any other.
local rt = {
  "feature f",
  "  contains",
  "    a.lua",
  "feature f",
  "  contains",
  "    b.lua",
}
H.eq(table.concat(map.serialize(map.parse(rt)), "\n"), table.concat(rt, "\n"), "round-trip is unaffected")

-- A FEATURE KEEPS ITS OWN PROSE. Two-space text under a feature, above its
-- members, is the sentence saying what the capability IS. The syntax file
-- has always colored it as the one piece of writing a reader most needs;
-- the parser dropped it, so nothing downstream could use it — and a
-- whole-feature cast wants it most of all, since it is the statement of the
-- thing being changed.
local prosed = map.parse({
  "feature Tailor a checklist to your own situation",
  "  Describe your circumstances in ordinary words and the compiler",
  "  selects from the vetted steps.",
  "  route copy",
  "    the tailored copy, decoded from the link",
  "  Prose at two spaces is the feature's wherever it sits — indentation is",
  "  the grammar, not position.",
}, { route = true })
H.eq(#prosed.features[1].desc, 4, "every two-space sentence belongs to the feature")
H.eq(prosed.features[1].desc[1]:find("Describe your circumstances", 1, true), 1, "in order")
H.eq(
  prosed.features[1].desc[3]:find("Prose at two spaces", 1, true),
  1,
  "including prose that follows a member — four spaces would have made it the member's"
)
H.eq(#prosed.features[1].claims[1].desc, 1, "and the four-space note is still the member's")
H.eq(#map.parse({ "feature bare" }, {}).features[1].desc, 0, "a feature with no prose has none")

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
