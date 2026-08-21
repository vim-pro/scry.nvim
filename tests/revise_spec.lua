-- A project-wide intent, cast across the map itself: what leaves scry for
-- a whole-map revision, read byte by byte.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local revise = require("scry.revise")

local KINDS = require("scry.kinds").all({
  kinds = { route = { path = "src/pages/{name}.astro" } },
})

local built = revise.build(
  "split the practices group into scheduling and attendance",
  KINDS,
  { route = { "c/[slug]", "print" } },
  { "lua" },
  { "src/lib/orphan.ts" }
)

H.ok(built:find("ENTIRE feature map", 1, true) ~= nil, "the model is told the stakes: whole map in, whole map out")
H.ok(built:find("anything you leave out is deleted", 1, true) ~= nil, "and that omission is deletion")
H.ok(built:find("split the practices group", 1, true) ~= nil, "the intent travels")
H.ok(built:find("def, module, route", 1, true) ~= nil, "the kinds in force, and nothing else")
H.ok(built:find("route: c/[slug], print", 1, true) ~= nil, "with real names off disk")
H.ok(built:find("grounded by a parser for: lua", 1, true) ~= nil, "and the honest def rung")
H.ok(built:find("Touch ONLY what the intent requires", 1, true) ~= nil, "preservation is the first rule")
H.ok(built:find("Never drop a `never` or `exercises` claim", 1, true) ~= nil, "the evidence claims are protected")
H.ok(built:find("src/lib/orphan.ts", 1, true) ~= nil, "the unclaimed files ride along as ground")
H.ok(built:find("flush%-left line of plain words") ~= nil, "the heading grammar is stated")

-- With nothing unclaimed, the section says so rather than dangling.
local bare = revise.build("x", KINDS, {}, nil, {})
H.ok(bare:find("(none)", 1, true) ~= nil, "an empty worklist is stated, not implied")
H.ok(bare:find("checked textually here", 1, true) ~= nil, "no parser is said plainly too")

H.done("revise_spec PASS")
