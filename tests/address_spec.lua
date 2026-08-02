-- Giving a capability an address: you say the feature in your own words, and
-- scry finds what it is made of.
--
-- This is the other direction from drafting. A drafting sweep starts at the
-- FILES nothing describes and writes features to cover them — bottom-up,
-- whole-project, answering "what is this repo". This starts at a capability
-- you already have in mind and answers "what is it made of", which is the
-- question you have when you sit down to change something.
--
-- It existed because the loop still had one hand-typed step. To cast `~` at
-- a feature you needed its members; to get its members you typed file paths
-- by hand — which means knowing the layout before you are allowed to
-- describe the product. Exactly backwards.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local address = require("scry.address")
local mapmod = require("scry.map")

local KINDS = require("scry.kinds").all({
  kinds = { route = { path = "src/pages/{name}.astro" } },
})

-- 1) THE REQUEST. The feature's name is the question; everything else is
-- what scry knows that the reader should not have to type.
local req = address.request("Read a checklist as markdown or JSON", {
  "src/pages/[slug].md.ts",
  "src/pages/[slug].json.ts",
  "src/lib/db.ts",
}, KINDS, { ["src/lib/db.ts"] = "Browse the library" })

H.ok(req.user:find("Read a checklist as markdown", 1, true) ~= nil, "the capability is named")
H.ok(req.user:find("src/pages/[slug].json.ts", 1, true) ~= nil, "the project's files are offered")
H.ok(req.user:find("module", 1, true) ~= nil, "with the kinds it may use")
H.ok(req.user:find("route <name>", 1, true) ~= nil, "including a project's own declared kind")
H.ok(req.user:find("src/pages/{name}.astro", 1, true) ~= nil, "and where that kind's files live")

-- A FILE ANOTHER FEATURE CLAIMS IS OFFERED ANYWAY, and labeled. One file can
-- serve two capabilities; withholding it to keep the unclaimed count tidy
-- would make this address wrong on purpose. Saying who else claims it is what
-- lets an answer notice it is re-describing something already described —
-- the failure that took one map to 301 features.
H.ok(req.user:find("src/lib/db.ts", 1, true) ~= nil, "a claimed file is still a candidate")
H.ok(req.user:find("already part of: Browse the library", 1, true) ~= nil, "and says who has it")

-- It must not ask for a `feature` line: the feature is already named, and a
-- second one would open a second feature rather than fill this one.
H.ok(req.system:find("Emit no `feature` line", 1, true) ~= nil, "the answer is a body, not a new feature")

-- 2) THE PARSER. Prose first, then members, and the SAME test map.parse
-- makes: a line is a member only when its first word is a kind this project
-- knows. Guessing by shape once turned the second word of a sentence into a
-- file path.
local lines, n = address.parse(table.concat({
  "Every checklist is fetchable as its source markdown or as structured JSON.",
  "module src/pages/[slug].md.ts",
  "module src/pages/[slug].json.ts",
  "route c/[slug]",
}, "\n"), KINDS)
H.eq(n, 3, "three members read")
H.eq(lines[1], "  Every checklist is fetchable as its source markdown or as structured JSON.", "prose kept, indented")
H.eq(lines[2], "  module src/pages/[slug].md.ts", "a member at the grammar's indent")
H.eq(lines[4], "  route c/[slug]", "a declared kind is a member too")

-- The whole point is that this parses back into the claims it looks like.
local reparsed = mapmod.parse(vim.list_extend({ "feature f" }, lines), KINDS)
H.eq(#reparsed.claims, 3, "and the result reparses as three claims, not as prose")
H.eq(#reparsed.features[1].desc, 1, "with the sentence kept as the feature's own")

-- An UNKNOWN kind is prose, not a claim. A model inventing `endpoint` when
-- the project has no such kind must cost a sentence, never a claim that
-- nothing will ever check.
local _, invented = address.parse("endpoint /api/compile", KINDS)
H.eq(invented, 0, "an invented kind is not a member")

-- Fences and un-filled placeholders are dropped rather than kept as prose.
local fenced, fn = address.parse("```\n<kind> <target>\nmodule a.ts\n```", KINDS)
H.eq(fn, 1, "the real member survives a fence")
H.eq(#fenced, 1, "and the shape's own placeholder is not mistaken for a sentence")

-- Prose AFTER the members is the model explaining itself, and explanation is
-- not description — it would land in the map as a sentence nobody wrote.
local trailing = address.parse("module a.ts\nI chose this file because it exports the handler.", KINDS)
H.eq(#trailing, 1, "commentary after the members is dropped")

-- 3) WHICH FEATURES WANT ONE. A feature with members has an address.
local map_ = mapmod.parse({
  "feature named and nothing else",
  "feature already made of something",
  "  module a.lua",
  "feature made of something that is not there yet",
  "  module does/not/exist.lua",
}, KINDS)
H.eq(address.wanted(map_.features[1]), true, "a feature with nothing under it wants an address")
H.eq(address.wanted(map_.features[2]), false, "one with members has one")

-- AND A MEMBER THAT DOES NOT HOLD IS STILL AN ADDRESS. A claim pointing at a
-- file that does not exist yet is work you described ON PURPOSE — it is how
-- you add a capability (|scry-compose|) — so re-addressing it would delete
-- the thing you were about to build.
H.eq(address.wanted(map_.features[3]), false, "an absent member is a description, not a gap")

H.done("address_spec PASS")
