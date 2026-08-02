-- Object recovery: the drafting pass, and the one property that makes it
-- safe to let a machine write into the map at all.
--
-- The load-bearing assertion is at the bottom: a drafted claim is NOT owned.
-- The glass watcher records `authored` for any claim that appears in the
-- buffer, because appearing under your edits is the authoring gesture — and a
-- machine's typing appears identically and means the opposite. If that
-- distinction ever breaks, a drafting pass silently converts a hundred
-- unread claims into a hundred beliefs you are recorded as holding.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local recover = require("scry.recover")
local prov = require("scry.provenance")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local EXISTING_PROSE = "Transport only: no UI, no lists."
local m = map.parse({
  "feature you can reach a model",
  "  " .. EXISTING_PROSE,
  "  contains",
  "    lua/providers/cli.lua:request",
})
local UNCLAIMED = { "lua/auth.lua", "lua/store.lua", "plugin/thing.lua" }

-- 1) WHAT LEAVES. build() is pure so this can be read rather than trusted.
local built = recover.build(m, UNCLAIMED)

-- THE WORKLIST TRAVELS IN THE REQUEST, NOT THE BUFFER. It used to be the
-- region, so a draft opened by pasting every undescribed path into the
-- glass — a screen of file names nobody asked to read, with the narration
-- buried above them. The model needs the list; the buffer needs a place for
-- the narration to stream into while the work happens.
for _, path in ipairs(UNCLAIMED) do
  H.ok(built.intent:find(path, 1, true) ~= nil, "the request names " .. path)
end
local worklist = table.concat(built.lines, "\n")
H.eq(#built.lines, 2, "and the buffer gets two lines, whatever the project's size")
for _, path in ipairs(UNCLAIMED) do
  H.eq(worklist:find(path, 1, true), nil, "no path is pasted into the buffer: " .. path)
end
H.ok(worklist:find("^%-%-") ~= nil, "both of which are prose, so a rejected draft leaves nothing")
H.ok(built.intent:find("feature <a statement", 1, true) ~= nil, "the grammar goes out")
-- THE VOCABULARY IS IN THE PROMPT, and it is closed. Asked for "the files",
-- a model returns a list of files: the first real draft came back with
-- eighty-six paths, which is the implementation wearing a product's clothes
-- one rung up from the ninety-seven functions. Asked for the kinds this
-- product HAS, it names routes and commands.
H.ok(built.intent:find("<kind> <name>", 1, true) ~= nil, "the member shape goes out")
H.ok(built.intent:find("TYPED OBJECT", 1, true) ~= nil, "and what a member is")
local typed = recover.build(m, UNCLAIMED, { route = true, command = true, module = true, def = true })
H.ok(typed.intent:find("command, def, module, route", 1, true) ~= nil, "the kinds in force are listed")
H.ok(typed.intent:find("PRODUCT before", 1, true) ~= nil, "product kinds before code kinds")

-- Altitude is the whole reason this pass can be useful rather than noise: a
-- machine left to itself drafts subfunctions, which is the failure the
-- feature layer exists to prevent.
H.ok(built.intent:find("one sitting", 1, true) ~= nil, "the sea-level test goes out")
H.ok(built.intent:find("the auth system", 1, true) ~= nil, "with the grouping it must not produce")
H.ok(built.intent:find("validate the token", 1, true) ~= nil, "and the subfunction it must not produce")
H.ok(built.intent:find("what is THERE", 1, true) ~= nil, "claims must describe what is there")

-- A drafting pass must not write prohibitions. One lands outside the repo,
-- unversioned, and narrows every future cascade; one nobody read is worse
-- than none.
H.ok(built.intent:find("Do not write a `never` block", 1, true) ~= nil, "no prohibitions may be drafted")

-- Existing feature NAMES go out (so a pass does not re-describe what is
-- already described); their prose does not.
H.ok(built.intent:find("you can reach a model", 1, true) ~= nil, "existing features are named")
H.eq(built.intent:find(EXISTING_PROSE, 1, true), nil, "but their prose is not sent")

-- 2) THE PLACEHOLDER IS INERT. If a request fails, or you never save, what is
-- left in the buffer must be prose — not half a feature.
local inert = map.parse(built.lines)
H.eq(#inert.features, 0, "the placeholder block declares no feature")
H.eq(#inert.claims, 0, "and no claims")

-- 3) DRIVE IT with a fake conjurer, capturing everything scry hands over.
local seen = nil
package.loaded["conjurer.operator"] = {
  conjure_region = function(buf, region, intent, opts)
    seen = { buf = buf, region = region, intent = intent, opts = opts }
  end,
}

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "feature you can reach a model",
  "  " .. EXISTING_PROSE,
  "  contains",
  "    lua/providers/cli.lua:request",
})
local before_lines = vim.api.nvim_buf_line_count(buf)

recover.draft(root, buf, m, UNCLAIMED)
H.ok(seen ~= nil, "conjurer was asked to cast")
H.eq(seen.buf, buf, "into the glass buffer")
H.eq(seen.region.kind, "line", "linewise")
H.ok(seen.opts.on_done ~= nil, "with on_done — which is what keeps the review tab shut")
H.ok(seen.opts.note:find("no feature claims", 1, true) ~= nil, "and a note saying why: " .. seen.opts.note)

-- The region handed over is exactly the placeholder, and nothing above it.
local region_lines = vim.api.nvim_buf_get_lines(buf, seen.region.srow, seen.region.erow, false)
H.eq(#region_lines, #built.lines, "the region is the placeholder block")
H.eq(region_lines[1], built.lines[1], "starting at its first line")
H.eq(region_lines[#region_lines], built.lines[#built.lines], "and ending at its last")
H.ok(seen.region.srow >= before_lines, "the existing map is not inside the region")

-- 4) THE SPLICE. Stand in for conjurer: replace the region with map text,
-- then fire on_done exactly as apply() would.
vim.api.nvim_buf_set_lines(buf, seen.region.srow, seen.region.erow, false, {
  "feature you can sign in",
  "  Credentials go in, a session comes back.",
  "  contains",
  "    lua/auth.lua:sign_in",
  "    lua/store.lua:session_put",
  "    plugin/thing.lua",
})
seen.opts.on_done(nil)

local after = map.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
H.eq(#after.features, 2, "the draft is in the map")
local drafted = {}
for _, c in ipairs(after.claims) do
  if c.feature == "you can sign in" then
    drafted[#drafted + 1] = c
  end
end
H.eq(#drafted, 3, "with its three claims")
H.eq(#map.footprint(after.features[2]), 3, "and a footprint covering all three files")

-- 5) THE PROPERTY. A drafted claim is inventory, not a belief. Every one of
-- them is registered as drafted, so the glass watcher declines to record your
-- authorship of a machine's typing — and `owned` stays false, which is what
-- puts them in the header's untouched count.
for _, c in ipairs(drafted) do
  H.ok(prov.drafted[map.claim_id(c)] == true, "registered as drafted: " .. c.target)
  H.eq(prov.owned(root, c), false, "and not owned: " .. c.target)
end

-- 6) EDITING A DRAFT IS HOW IT BECOMES YOURS, and this falls out of the id
-- rather than being arranged: a claim id hashes the claim's text, so an
-- edited draft is a claim nothing has registered, and the watcher records it.
local edited = {
  kind = drafted[1].kind,
  target = "lua/auth.lua:sign_in_with_password",
  feature = drafted[1].feature,
  lnum = drafted[1].lnum,
}
H.eq(prov.drafted[map.claim_id(edited)], nil, "an edited draft is not registered as drafted")
prov.record(root, edited, "authored")
H.eq(prov.owned(root, edited), true, "so editing it is authorship")

-- 7) A FAILED REQUEST must not rearrange the buffer under you.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "feature a", "  contains", "    x.lua:y" })
seen = nil
recover.draft(root, buf2, map.parse(vim.api.nvim_buf_get_lines(buf2, 0, -1, false)), { "z.lua" })
local lines_before_failure = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
seen.opts.on_done("provider exploded")
H.eq(
  table.concat(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), "\n"),
  table.concat(lines_before_failure, "\n"),
  "a failed draft leaves the buffer exactly as it was"
)
H.eq(#map.parse(vim.api.nvim_buf_get_lines(buf2, 0, -1, false)).features, 1, "and adds no feature")


-- A FAILED DRAFT LEAVES ITS BLOCK — the notification says `u` clears it —
-- and re-running instead of undoing stacked a second on the first. Inert
-- prose, so nothing broke, but the top of the map filled with the wreckage
-- of attempts and there is no reading of two of them that means anything.
local stacked = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(stacked, 0, -1, false, {
  "-- scry: drafting features for 72 undescribed file(s)…",
  "-- Reject to discard. Nothing below is a belief until you edit it.",
  "",
  "feature something real someone kept",
  "  def lua/a.lua:x",
})
require("scry").setup({ provider = function() end })
pcall(recover.draft, vim.fn.tempname(), stacked, map.parse({}), { "lua/z.lua" })
local after = vim.api.nvim_buf_get_lines(stacked, 0, -1, false)
local blocks = 0
for _, l in ipairs(after) do
  if l:match("^%-%- scry: drafting features for ") then
    blocks = blocks + 1
  end
end
H.eq(blocks, 1, "one drafting block, never two")
H.ok(
  table.concat(after, "\n"):find("feature something real someone kept", 1, true) ~= nil,
  "and the map around it is untouched"
)


-- ONE PASS IS ONE BATCH. The worklist went out whole, and at seventy-two
-- files that already ran past a five-minute timeout — at twenty thousand it
-- is not a long request but an impossible one. Iterating is natural because
-- a kept draft claims what it described, so the next run sees what is left.
local many = {}
for i = 1, 300 do
  many[i] = ("src/mod%03d.js"):format(i)
end
local capped = vim.api.nvim_create_buf(false, true)
require("scry").setup({ provider = function() end })
pcall(recover.draft, vim.fn.tempname(), capped, map.parse({}), many)
local sent = table.concat(vim.api.nvim_buf_get_lines(capped, 0, -1, false), "\n")
H.ok(sent:find("drafting features for 12 undescribed", 1, true) ~= nil, "a pass takes a bounded batch: " .. sent:sub(1, 60))
H.eq(sent:find("300 undescribed", 1, true), nil, "not the whole three hundred")

H.done("recover_spec PASS")
