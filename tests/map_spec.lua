-- The map parser: lossless round-trips, claim extraction, stamps, and the
-- rule that there are no parse errors — only claims and prose.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")

local SRC = {
  "# providers",
  "  files lua/conjurer/providers/*.lua, lua/extra/*.lua",
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
  "some stray prose at concern level",
  "",
  "# empty concern",
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
H.eq(#m.concerns, 2, "two concerns")
H.eq(m.concerns[1].name, "providers", "concern name")
H.eq(#m.concerns[1].globs, 2, "two file globs")
H.eq(m.concerns[1].globs[2], "lua/extra/*.lua", "glob trimmed")
H.eq(#m.claims, 4, "four claims total")
H.eq(#m.concerns[2].claims, 0, "prose-only concern has no claims")

-- 3) claim details
local c1, c2, c3, c4 = m.claims[1], m.claims[2], m.claims[3], m.claims[4]
H.eq(c1.kind, "contains", "claim 1 kind")
H.eq(c1.target, "lua/conjurer/providers/cli.lua:request", "stamped claim target excludes the stamp")
H.eq(c1.stamp.user, "michael", "stamp user (without @)")
H.eq(c1.stamp.date, "2026-07-26", "stamp date")
H.eq(c1.stamp.hash, "3f9a01", "stamp hash")
H.eq(c2.stamp, nil, "unstamped claim")
H.eq(c3.kind, "calls", "calls section")
H.eq(c4.kind, "never", "never section")
H.eq(c4.target, "vim\\.ui\\.", "never target is the verbatim pattern")
H.eq(c4.concern, "providers", "claims know their concern")

-- 4) blank line ends a section: prose after the never block is not a claim
H.eq(m.claims[#m.claims].target, "vim\\.ui\\.", "stray prose never became a claim")

-- 5) no parse errors on garbage — everything unrecognized is prose, and a
-- dedented line ENDS its section (claims after it are prose until the next
-- section header).
local weird = map.parse({
  "?????",
  "   ",
  "# c",
  "  contains",
  "    real.lua:sym",
  "not-indented-enough",
  "    looks-like-a-claim-but-is-prose",
})
H.eq(#weird.claims, 1, "claim before the dedent parsed; line after it is prose")
H.eq(weird.claims[1].target, "real.lua:sym", "the real claim survived its weird neighbors")

-- 6) ratify: stamp, staleness, restamp
local ratify = require("scry.ratify")
local m2 = map.parse(vim.deepcopy(SRC))
local claim = m2.claims[2]
H.eq(ratify.ratified(claim), false, "unstamped claim is unratified")
ratify.stamp(m2, claim, "w0zro", "2026-07-26")
H.eq(ratify.ratified(claim), true, "stamped claim is ratified")
-- the stamp landed in the LINE, and reparsing sees it
local m3 = map.parse(map.serialize(m2))
H.eq(m3.claims[2].stamp.user, "w0zro", "stamp survives serialize+reparse")
H.eq(ratify.ratified(m3.claims[2]), true, "reparsed claim still ratified")
-- editing the target invalidates the hash mechanically
m3.claims[2].target = "lua/conjurer/providers/known.lua:resolve_api_v2"
H.eq(ratify.ratified(m3.claims[2]), false, "edited claim is unratified again")
-- claim 1's pre-existing stamp hash doesn't match its real sha (fixture
-- used a made-up hash) — staleness catches fabricated stamps too
H.eq(ratify.ratified(m3.claims[1]), false, "wrong-hash stamp reads as unratified")

-- 7) author() must return exactly one value: it's called inline as
-- stamp(map, claim, author(config)), so a second return value would land in
-- the date parameter and produce a stamp that fails its own format.
local a, extra = ratify.author({ author = "" })
H.eq(extra, nil, "author() returns a single value")
H.ok(type(a) == "string" and a ~= "", "author() resolved a name")
-- and stamp() defends the date shape regardless of what it is handed
local m4 = map.parse({ "# c", "  contains", "    f.lua:sym" })
ratify.stamp(m4, m4.claims[1], "someone", 0)
H.eq(ratify.ratified(map.parse(map.serialize(m4)).claims[1]), true, "a bogus date is replaced, stamp stays valid")

H.done("map_spec PASS")
