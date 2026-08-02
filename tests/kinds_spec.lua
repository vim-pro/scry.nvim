-- What a product is made of. A member names a typed OBJECT now, not an
-- evidence relation, and the kind is what makes a map read at the product's
-- altitude instead of the implementation's.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local kinds = require("scry.kinds")
local mapmod = require("scry.map")

-- 1) TWO KINDS NEED NO DECLARING. `module` needs no parser — a file is on
-- disk or it is not — which is why it is the one kind that works in every
-- language, and why a JavaScript project is checkable at all today.
local bare = kinds.all({})
H.ok(bare.module ~= nil, "module is universal")
H.ok(bare.def ~= nil, "def is universal")
H.eq(bare.route, nil, "and nothing else is assumed")

-- 2) A PROJECT DECLARES THE REST. The archived vim.pro hardcoded six kinds
-- and they were Neovim's six — that vocabulary describes plugins. Routes
-- describe checklists.org. Neither list is the right one for both, so the
-- product-shaped ones come from the repo.
local declared = kinds.all({
  kinds = {
    route = { path = "src/pages/{name}.astro" },
    command = { grep = 'nvim_create_user_command%("{name}"' },
  },
})
H.ok(declared.route ~= nil, "a declared kind is in force")
H.eq(declared.route.probe, "path", "and knows how it is probed")
H.eq(declared.command.probe, "grep", "each by its own means")
H.ok(declared.module ~= nil, "without displacing the builtins")

-- A repo may not redefine what a builtin or a relation means: those are the
-- vocabulary everything else is described in.
local hostile = kinds.all({ kinds = { module = { path = "x" }, never = { path = "y" } } })
H.eq(hostile.module.declared, nil, "a repo cannot redefine module")
H.eq(hostile.never, nil, "nor turn a relation into an object")

-- 3) {name} IS ESCAPED FOR THE PROBE IT ENTERS. A route named `[slug]` is a
-- character class to ripgrep; unescaped it would match `s`, `l`, `u`, `g`
-- and report a page that does not exist.
H.eq(kinds.expand("src/pages/{name}.astro", "[slug]", "none"), "src/pages/[slug].astro", "a path takes the name whole")
local rx = kinds.expand("export function {name}", "[slug]", "regex")
H.ok(rx:find("\\[slug\\]", 1, true) ~= nil, "a grep pattern escapes it: " .. rx)

-- 4) A MEMBER IS TOLD FROM PROSE BY ITS KIND, not by its shape. Prose and a
-- member are the same shape — `route /a` and `Feature prose.` are both two
-- words at two spaces — so parse takes the kinds in force. Guessing by
-- shape silently turned the second word of a sentence into a claim.
local m = mapmod.parse({
  "feature a reader can follow a link someone sent them",
  "  Feature prose that looks exactly like a member.",
  "",
  "  route [slug]",
  "    The run view — the member's OWN intent, not the feature's.",
  "    A second line of it.",
  "  module src/lib/run.js",
  "  def src/lib/run.js:initChecklist",
}, { route = true })
H.eq(#m.claims, 3, "three members, and the prose is not one of them")
H.eq(m.claims[1].kind, "route", "the declared kind survives parsing")
H.eq(m.claims[1].target, "[slug]", "with its name intact")
H.eq(#m.claims[1].desc, 2, "a member carries its own intent")
H.eq(m.claims[1].desc[1]:find("run view", 1, true) ~= nil, true, "which is the thing a re-conjure could regenerate it from")
H.eq(#m.claims[2].desc, 0, "and a member without intent has none")

-- An undeclared kind is PROSE, not a claim. Silence beats a claim nothing
-- can check: `endpoint compile` in a project with no endpoint kind is a
-- sentence, and scry has no business pretending otherwise.
local undeclared = mapmod.parse({ "feature f", "  endpoint compile" }, {})
H.eq(#undeclared.claims, 0, "an undeclared kind stays prose")

-- 5) LEGACY MAPS KEEP THEIR MEANING. `contains` was doing two jobs and its
-- shape said which: with a symbol it asserted a definition, without one a
-- file. Reading it as the kind it meant is a renaming, not a
-- reinterpretation — no map anyone wrote changes meaning by being reparsed.
local legacy = mapmod.parse({
  "feature f",
  "  contains",
  "    lua/a.lua:sym",
  "    lua/b.lua",
  "  never",
  "    print%(",
})
H.eq(legacy.claims[1].kind, "def", "contains with a symbol always meant def")
H.eq(legacy.claims[2].kind, "module", "and without one, module")
H.eq(legacy.claims[3].kind, "never", "a relation stays a relation")

-- 6) A KIND THE PROJECT DOES NOT KNOW IS UNCHECKED, NAMED, AND SAYS WHAT TO
-- DO — never quietly passed. Silence must not read as ✓.
local seen
require("scry.resolver").check(
  require("scry.resolvers.ts_rg"),
  { root = ".", globs = {}, kinds = {} },
  { kind = "endpoint", target = "compile", feature = "f" },
  function(v)
    seen = v
  end
)
H.eq(seen.status, "unchecked", "an unknown kind is unchecked, not backed")
H.ok(seen.label:find("config.json", 1, true) ~= nil, "and the label says the remedy: " .. seen.label)

H.done("kinds_spec PASS")
