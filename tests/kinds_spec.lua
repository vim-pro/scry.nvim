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

-- 7) WHAT A NAME LOOKS LIKE, taken off disk. A member's name is exactly the
-- text the probe substitutes, and nothing said so — so a drafter wrote what
-- the kind means to a person: `endpoint /index.json`, a URL. Scry pasted it
-- into `src/pages/api/{name}.ts`, got `src/pages/api//index.json.ts`, and
-- reported it absent — accurately, about a path nobody meant.
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/src/pages/api", "p")
vim.fn.writefile({ "" }, proj .. "/src/pages/api/compile.ts")
vim.fn.writefile({ "" }, proj .. "/src/pages/api/suggest.ts")
vim.fn.writefile({ "" }, proj .. "/src/pages/index.astro")
local found = kinds.examples(proj, { path = "src/pages/api/{name}.ts" }, 6)
H.eq(#found, 2, "both endpoints are discovered")
H.eq(found[1], "compile", "as the text that fills {name}")
H.eq(found[2], "suggest", "and nothing else")
-- The suffix has to match too, or every file under the prefix comes back.
H.eq(#kinds.examples(proj, { path = "src/pages/{name}.astro" }, 6), 1, "the suffix narrows it")
H.eq(#kinds.examples(proj, { grep = "x{name}" }, 6), 0, "a grep-probed kind has no paths to enumerate")

-- And a name that round-trips: expanding a discovered name reproduces the
-- file it came from. That is the property the draft depends on.
H.eq(kinds.expand("src/pages/api/{name}.ts", found[1], "none"), "src/pages/api/compile.ts", "discovery and expansion agree")

-- 8) A PATH-PROBED KIND LOCATES ITS FILE. This returned nil, on the reasoning
-- that a declared kind is found by evidence rather than named outright — but
-- the probe is a path template and the member's name is what fills it, which
-- is the same substitution `examples` above runs in reverse.
--
-- Measured cost of the nil, on a real drafting pass: `route c/[slug]` located
-- nothing, so src/pages/c/[slug].astro was never counted as described, so it
-- stayed on the undescribed worklist, so every batch was asked about it
-- again. The drafter — told not to reuse existing feature NAMES — reworded
-- instead, and since a claim's id carries its feature name, each rewording
-- read as progress. It reached 301 features over 60 distinct targets, one
-- route claimed by 73 of them, and reported 24 files unclaimed while eleven
-- of those were claimed dozens of times over.
local located = kinds.all({ kinds = { route = { path = "src/pages/{name}.astro" } } })
H.eq(
  mapmod.claim_path({ kind = "route", target = "c/[slug]" }, located),
  "src/pages/c/[slug].astro",
  "a route names the page it is"
)
H.eq(mapmod.claim_path({ kind = "module", target = "src/lib/db.js" }, located), "src/lib/db.js", "module is unchanged")
H.eq(mapmod.claim_path({ kind = "def", target = "lua/a.lua:sym" }, located), "lua/a.lua", "and so is def")

-- Without the kinds in force there is nothing to expand against, so the old
-- answer stands rather than a guess.
H.eq(mapmod.claim_path({ kind = "route", target = "c/[slug]" }), nil, "no kinds, no location")

-- A GREP-PROBED KIND STILL LOCATES NOTHING. A pattern can match anywhere; it
-- is not a place, and pretending otherwise would claim files at random.
local grepped = kinds.all({ kinds = { command = { grep = 'command%("{name}"' } } })
H.eq(mapmod.claim_path({ kind = "command", target = "ScryDraft" }, grepped), nil, "a pattern is not a path")
H.eq(mapmod.claim_path({ kind = "never", target = "print%(" }, located), nil, "nor is a prohibition")

-- And the feature's footprint follows, which is what divergence counts.
local withroutes = mapmod.parse({
  "feature someone can open a checklist",
  "  route c/[slug]",
  "  module src/lib/db.js",
}, located)
local fp = mapmod.footprint(withroutes.features[1], located)
table.sort(fp)
H.eq(#fp, 2, "both members are places")
H.eq(fp[1], "src/lib/db.js", "the module")
H.eq(fp[2], "src/pages/c/[slug].astro", "and the page the route is")

H.done("kinds_spec PASS")
