-- Aiming: from what you want, to the thing it is about.
--
-- Nobody sits down wanting to look at a map. You sit down wanting to DO
-- something, and the map is how scry finds the capability it belongs to — so the intent
-- is the front door and the map is what answers it.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local aim = require("scry.aim")
local mapmod = require("scry.map")

local MAP = mapmod.parse({
  "feature Read a checklist as markdown or JSON instead of a web page",
  "  Every checklist is fetchable as its source markdown or as structured JSON.",
  "  module a.ts",
  "feature Work through a checklist and keep your place",
  "  module b.ts",
}, {})

-- 1) THE REQUEST carries the work and the capabilities the product already
-- has. Their descriptions travel too: two names can look alike and mean
-- different things, and the sentence under one is what says which.
local req = aim.request("add a PDF export", MAP)
H.ok(req.user:find("add a PDF export", 1, true) ~= nil, "the work is stated")
H.ok(req.user:find("Read a checklist as markdown", 1, true) ~= nil, "existing capabilities are offered")
H.ok(req.user:find("Every checklist is fetchable", 1, true) ~= nil, "with what each one is for")
H.ok(req.system:find("Prefer MATCH", 1, true) ~= nil, "and the bias is toward the feature you already have")

-- AN EMPTY MAP SAYS SO OUTRIGHT. An empty heading under an instruction to
-- "prefer MATCH" reads as a trick question.
local empty = aim.request("add a PDF export", mapmod.parse({}, {}))
H.ok(empty.user:find("the map is empty", 1, true) ~= nil, "an empty map is stated, not implied")

-- 2) THE PARSER. Two shapes, one line.
local kind, name = aim.parse("MATCH: Work through a checklist and keep your place", MAP)
H.eq(kind, "match", "an existing capability is matched")
H.eq(name, "Work through a checklist and keep your place", "and named exactly")

local nkind, nname = aim.parse("NEW: Take a checklist away as a PDF", MAP)
H.eq(nkind, "new", "work the map does not cover is new")
H.eq(nname, "Take a checklist away as a PDF", "with a name of its own")

-- A MATCH THAT IS NOT IN THE MAP IS NOT A MATCH. The model paraphrasing a
-- feature it meant to match would otherwise move the cursor to a feature
-- nobody wrote — or, worse, be silently resolved to the nearest one, which is
-- how you end up casting an intent at the wrong capability.
local para, pname = aim.parse("MATCH: Reading checklists as markdown or JSON", MAP)
H.eq(para, "new", "a paraphrase is treated as new rather than resolved to something near it")
H.eq(pname, "Reading checklists as markdown or JSON", "and keeps the name it gave")

-- Prose around the line does not break it, and an answer with neither shape
-- is nothing rather than a guess.
H.eq(aim.parse("Sure!\n\nMATCH: Work through a checklist and keep your place\n", MAP), "match", "prose is ignored")
H.eq(aim.parse("I am not sure what you mean.", MAP), nil, "an answer in neither shape aims nowhere")
H.eq(aim.parse("", MAP), nil, "and neither does an empty one")

-- 3) THE INTENT IS REMEMBERED, so `~` does not ask the same question twice.
-- Aiming stops at the cursor on purpose — you see the files before
-- anything is cast across them — and that would be a poor trade if agreeing then
-- cost you retyping the sentence you already wrote.
local compose = require("scry.compose")
-- The provider is never reached — every prompt below is cancelled — but the
-- guard that conjurer is installed runs first, and this suite does not have
-- it on the runtimepath.
package.loaded["conjurer"] = package.loaded["conjurer"] or { config = {} }
local asked
local real_input = vim.ui.input
vim.ui.input = function(opts, cb)
  asked = opts
  cb(nil) -- cancel: this spec is about what the prompt OFFERS
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "feature Read a checklist as markdown or JSON instead of a web page",
  "  module a.ts",
})
vim.api.nvim_win_set_buf(0, buf)
local glass = require("scry.glass")
glass._state.buf, glass._state.root = buf, "."
vim.api.nvim_win_set_cursor(0, { 1, 0 })

compose.remember("add a PDF export")
compose.start()
H.eq(asked.default, "add a PDF export", "the prompt comes up pre-filled with the intent you already gave")
H.ok(asked.prompt:find("Read a checklist", 1, true) ~= nil, "and names the capability it will land on")

-- CLEARED ON USE, NOT ON SUCCESS. The prompt above was cancelled; a
-- remembered intent that survived that would come back later on an unrelated
-- feature, which is the worst way for a convenience to behave.
asked = nil
compose.start()
H.eq(asked.default, nil, "a cancelled prompt does not leave the intent lying around")

vim.ui.input = real_input

H.done("aim_spec PASS")
