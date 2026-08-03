-- The plan: what an intent will do, written where you can edit it.
--
-- Aiming used to stop at the cursor with the change entirely in your head —
-- you saw WHERE and knew what you asked for, but which files would change,
-- which would be created and what would go away lived nowhere until the cast
-- came back with it already done. Review after the fact, on a tool whose
-- whole shape is look-then-fire.
--
-- The plan is BUFFER TEXT in the map's own grammar: notes under members, new
-- members for files to create. Altering it is editing lines, discarding it
-- is `u`, building it is `~` — no accept/reject UI, because the review
-- surface for a suggestion in a text file is the text file.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local plan = require("scry.plan")
local mapmod = require("scry.map")

local KINDS = require("scry.kinds").all({
  kinds = { route = { path = "src/pages/{name}.astro" } },
})

local FEATURE = mapmod.parse({
  "feature Take a checklist away as a PDF",
  "  Turns the on-screen checklist into a clean sheet of paper.",
  "  route c/[slug]",
  "  def src/styles/global.css",
}, KINDS).features[1]

local ON_DISK = {
  ["src/pages/c/[slug].astro"] = { "<h1>checklist</h1>" },
  ["src/styles/global.css"] = { "body { color: black }" },
}
local function read(path)
  return ON_DISK[path]
end

-- 1) THE REQUEST. The plan is decided from the same things you would decide
-- it from: the feature, the intent, what exists, and the code itself.
local req = plan.request(FEATURE, "add a printable PDF view", KINDS, {
  "src/pages/c/[slug].astro",
  "src/styles/global.css",
  "src/lib/site.js",
}, { ["src/lib/site.js"] = "Browse the library" }, read)

H.ok(req.user:find("Take a checklist away as a PDF", 1, true) ~= nil, "the feature is named")
H.ok(req.user:find("add a printable PDF view", 1, true) ~= nil, "and the intent")
H.ok(req.user:find("route c/[slug]", 1, true) ~= nil, "current members are listed")
H.ok(req.user:find("<h1>checklist</h1>", 1, true) ~= nil, "with their contents — a plan written")
H.ok(req.user:find("body { color: black }", 1, true) ~= nil, "without reading the code is a guess")
H.ok(req.user:find("already part of: Browse the library", 1, true) ~= nil, "other features' files are labeled")
H.ok(req.system:find("Repeat EVERY existing member", 1, true) ~= nil, "and the no-shrinking rule is stated")

-- A bare feature is told it is building from nothing, not shown an empty
-- heading that reads like a trick question.
local bare = mapmod.parse({ "feature Watch someone work" }, KINDS).features[1]
local breq = plan.request(bare, "x", KINDS, {}, nil, read)
H.ok(breq.user:find("none yet", 1, true) ~= nil, "a bare feature's plan starts from nothing, and says so")

-- 2) THE PARSER. A line is a member only when its first word is a kind this
-- project knows — the same rule as everywhere — and everything else attaches
-- to the member above it as its note.
local parsed = plan.parse(table.concat({
  "Here is the plan:",
  "route c/[slug]",
  "  add a print button that opens the print view",
  "def src/styles/global.css",
  "route print",
  "  the print-only sheet: steps, notes, no chrome",
}, "\n"), KINDS)
H.eq(#parsed, 3, "three members read")
H.eq(#parsed[1].notes, 1, "a touched member carries its note")
H.eq(#parsed[2].notes, 0, "an untouched member is bare")
H.eq(parsed[3].target, "print", "a new member arrives like any other")
-- The commentary before the first member went nowhere: not a member, and
-- nothing above it to be a note of.
H.eq(parsed[1].kind, "route", "prose before the first member is dropped, not misread")

-- 3) APPLY: one buffer edit into the feature's block.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "feature Take a checklist away as a PDF",
  "  Turns the on-screen checklist into a clean sheet of paper.",
  "  route c/[slug]",
  "  def src/styles/global.css",
  "    the print styles live here already",
  "",
  "feature Watch someone work",
  "  module a.lua",
})
local live = mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), KINDS).features[1]

plan.apply(buf, live, KINDS, {
  { kind = "route", target = "c/[slug]", notes = { "add a print button" } },
  { kind = "route", target = "print", notes = { "the print-only sheet" } },
  -- def src/styles/global.css deliberately DROPPED by this plan
})
local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local text = table.concat(after, "\n")

H.ok(text:find("  Turns the on%-screen checklist") ~= nil, "the feature's description is untouched")
H.ok(text:find("  route c/%[slug%]\n    add a print button") ~= nil, "a planned note lands under its member")
H.ok(text:find("  route print\n    the print%-only sheet") ~= nil, "a new member arrives with its note")

-- THE MACHINE MAY NOT SHRINK THE MAP. The plan omitted the stylesheet; it
-- comes back anyway, with the note it already had. Removing a member is an
-- edit only a person makes — `dd`, like anything else deleted.
H.ok(text:find("  def src/styles/global%.css") ~= nil, "a member the model dropped is re-added")
H.ok(text:find("    the print styles live here already", 1, true) ~= nil, "with its original note")

-- The next feature and the separator blank both survive.
H.ok(text:find("\n\nfeature Watch someone work") ~= nil, "the block boundary is preserved")
H.ok(text:find("  module a%.lua") ~= nil, "and the neighbor is untouched")

-- ...and the result reparses as the grammar it looks like, which is the
-- whole point of writing the plan in the grammar: `~` sends these notes.
local reparsed = mapmod.parse(after, KINDS)
H.eq(#reparsed.features[1].claims, 3, "three members after the plan")
H.eq(reparsed.features[1].claims[1].desc[1], "add a print button", "and the note IS the member's note")

-- 4) A RE-OPENED FEATURE'S OTHER BLOCKS ARE NOT OURS TO MOVE. A member
-- living in a later block is neither duplicated into this one nor re-added
-- as if it had been dropped.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, {
  "feature split",
  "  module a.lua",
  "feature other",
  "  module b.lua",
  "feature split",
  "  module c.lua",
})
local split = mapmod.parse(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), KINDS).features[1]
plan.apply(buf2, split, KINDS, {
  { kind = "module", target = "a.lua", notes = { "touch this" } },
  { kind = "module", target = "c.lua", notes = { "and this" } },
})
local after2 = table.concat(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), "\n")
local _, c_count = after2:gsub("module c%.lua", "")
H.eq(c_count, 1, "a member in another block is not duplicated into this one")
H.ok(after2:find("feature split\n  module a%.lua\n    touch this") ~= nil, "this block's member took its note")

-- 5) THE PLAN HAS A LIFECYCLE: pending, built, settled against what
-- actually happened.
--
-- A plan note and a member's ordinary description are the same grammar on
-- purpose, so the buffer alone cannot say "this row is about to change" —
-- the pending state is what says it, and it is session state like the last
-- cast.
plan.clear()
local c1 = { kind = "route", target = "c/[slug]", feature = "Take a checklist away as a PDF", desc = { "add a print button" } }
local c2 = { kind = "route", target = "print", feature = "Take a checklist away as a PDF", desc = { "the print-only sheet" } }
local c3 = { kind = "module", target = "src/lib/site.js", feature = "Take a checklist away as a PDF", desc = {} }
local other = { kind = "module", target = "a.lua", feature = "Browse the library", desc = { "a note" } }

H.eq(plan.mark(c1, "src/pages/c/[slug].astro", true), nil, "no pending plan, no words")

plan.pending = { feature = "Take a checklist away as a PDF" }
H.eq(plan.mark(c1, "src/pages/c/[slug].astro", true), "change", "a noted member whose file exists will change")
H.eq(plan.mark(c2, "src/pages/print.astro", false), "create", "one whose file is absent will be created")
H.eq(plan.mark(c3, "src/lib/site.js", true), nil, "an unnoted member is not the plan's to mark")
H.eq(plan.mark(other, "a.lua", true), nil, "another feature's notes are just its descriptions")

-- CLOSURE. The cast is checked against the plan it was given: each planned
-- row flips to what actually happened, and a planned member the cast never
-- touched says `skipped` rather than sitting there looking intended.
plan.settle("some other feature", { changed = { "x" }, created = {} })
H.eq(plan.pending.outcomes, nil, "a cast on another feature settles nothing")
plan.settle("Take a checklist away as a PDF", { changed = { "src/pages/c/[slug].astro" }, created = {} })
H.eq(plan.mark(c1, "src/pages/c/[slug].astro", true), "changed", "a planned change that happened says so")
H.eq(plan.mark(c2, "src/pages/print.astro", false), "skipped", "a planned member the cast did not touch says SKIPPED")
H.eq(plan.mark(c3, "src/lib/site.js", true), nil, "and an unplanned member still says nothing")

-- `:w` is the acceptance gesture: writing the map is accepting it, and the
-- plan's words have done their job.
plan.clear()
H.eq(plan.mark(c1, "src/pages/c/[slug].astro", true), nil, "a cleared plan marks nothing")

H.done("plan_spec PASS")
