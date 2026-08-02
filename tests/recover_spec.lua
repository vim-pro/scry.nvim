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

-- ONE COMMAND IS A PASS, NOT A REQUEST. A batch has to be small and a
-- project has thousands of files, so the two together mean one request can
-- never be the unit of work — asking someone to run :ScryDraft a hundred
-- and thirty times is asking them to be the loop. Each batch issues the
-- next when it lands.
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/src", "p")
for i = 1, 20 do
  vim.fn.writefile({ "-- " .. i }, ("%s/src/mod%02d.lua"):format(proj, i))
end
local casts = {}
require("scry").setup({
  provider = function() end,
})
local op = require("conjurer.operator")
local real_region = op.conjure_region
op.conjure_region = function(b, region, intent, opts)
  casts[#casts + 1] = { buf = b, opts = opts, intent = intent }
end

local pbuf = vim.api.nvim_create_buf(false, true)
recover.next_batch(proj, pbuf, true)
H.eq(#casts, 1, "a pass opens with one batch")
H.eq(recover.passing(), true, "and is running")

-- The draft lands: write what the model would have written, then tell
-- conjurer it is done. That is the moment the next batch is issued.
vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, {
  "feature someone can use the first twelve modules",
  "  module src/mod01.lua",
  "  module src/mod02.lua",
})
casts[1].opts.on_done(nil)
H.ok(H.wait(function()
  return #casts >= 2
end, 5000), "the next batch follows without being asked for")
H.ok(
  casts[2].intent:find("mod03.lua", 1, true) ~= nil,
  "and asks about what is undescribed NOW, not the rest of the old list"
)
H.eq(casts[2].intent:find("mod01.lua", 1, true), nil, "a file the last batch claimed is not asked about again")

-- A BATCH THAT DESCRIBES NOTHING ENDS THE PASS. Without this a file the
-- model declines to describe is asked about forever, and the pass is an
-- infinite loop that costs money on every turn of it.
casts[2].opts.on_done(nil)
H.eq(recover.passing(), false, "a batch that adds no claim stops the pass")
local n = #casts
vim.wait(200)
H.eq(#casts, n, "and no further batch goes out")

-- A FAILED REQUEST ends it too, which is what makes :ConjureCancel stop the
-- whole pass rather than one batch of it.
casts = {}
local fbuf = vim.api.nvim_create_buf(false, true)
recover.next_batch(proj, fbuf, true)
H.eq(recover.passing(), true, "running again")
casts[1].opts.on_done("canceled")
H.eq(recover.passing(), false, "a failure ends the pass")

-- AND A BATCH IS BOUNDED IN TIME by what the caller knows, not by a global
-- default. Twelve files came back in 51s, 55s, 84s, 89s and 265s across
-- real runs — conjurer's 300s default sits inside that spread, and a pass
-- that dies five minutes in has cost the wait and given nothing back.
H.ok(casts[1].opts.timeout_ms and casts[1].opts.timeout_ms > 300000, "a drafting batch gets longer than the default")

-- A BATCH THAT DESCRIBES NO NEW FILE ENDS THE PASS, whatever it wrote.
-- The guard used to count new claim ids, and a claim's id carries its
-- feature name — so a second feature about an already-described file
-- produced a fresh id and read as progress. On a real run that made the
-- pass unable to finish: eleven pages stayed on the worklist every round
-- while the drafter reworded around them, to 301 features over 60 targets.
casts = {}
local sbuf2 = vim.api.nvim_create_buf(false, true)
recover.next_batch(proj, sbuf2, true)
H.eq(recover.passing(), true, "a pass opens")
-- The model writes a feature, but one that claims nothing on the worklist —
-- the shape that used to loop forever.
vim.api.nvim_buf_set_lines(sbuf2, 0, -1, false, {
  "feature a feature about nothing on disk",
  "  module src/nowhere.lua",
})
casts[1].opts.on_done(nil)
H.ok(H.wait(function()
  return not recover.passing()
end, 5000), "and ends when the worklist did not shrink")
local n2 = #casts
vim.wait(200)
H.eq(#casts, n2, "with no further batch")

-- A pass that dies partway has still written every batch before it, and
-- those are kept — so what it says has to be "resume", not "failed".
casts = {}
local rbuf = vim.api.nvim_create_buf(false, true)
recover.next_batch(proj, rbuf, true)
vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, { "feature x", "  module src/mod01.lua" })
casts[1].opts.on_done(nil)
H.ok(H.wait(function()
  return #casts >= 2
end, 5000), "a second batch went out")
local said
local real_notify = vim.notify
vim.notify = function(msg)
  said = msg
end
casts[2].opts.on_done("timed out")
vim.notify = real_notify
H.ok(said and said:find("resumes", 1, true) ~= nil, "the failure says how to pick it up: " .. tostring(said))
H.ok(said:find("kept", 1, true) ~= nil, "and that the earlier batches survived")

-- :ScryDraftStop leaves the request in flight alone — it is already paid
-- for, and its result is a draft worth keeping.
casts = {}
local sbuf = vim.api.nvim_create_buf(false, true)
recover.next_batch(proj, sbuf, true)
recover.stop()
H.eq(recover.passing(), false, "stopped")
vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, { "feature x", "  module src/mod01.lua" })
casts[1].opts.on_done(nil)
vim.wait(200)
H.eq(#casts, 1, "the batch in flight still lands, and nothing follows it")

op.conjure_region = real_region

-- THE DRAFT IS TOLD HOW TO ADD TO WHAT EXISTS. "Do not repeat these
-- existing features" is a constraint on NAMES, and a model satisfies it by
-- rewording — which is how one pass reached 301 features over 60 files. The
-- request now carries the move that was missing: re-open a feature by name.
local exists = map.parse({
  "feature someone can work through a checklist",
  "  module src/run.js",
})
local built2 = recover.build(exists, { "src/lib/progress.js" }, { module = true }, {}, { "lua" })
H.ok(built2.intent:find("someone can work through a checklist", 1, true) ~= nil, "the existing feature is shown")
H.ok(built2.intent:find("ADD TO IT", 1, true) ~= nil, "with instructions to extend it")
H.eq(built2.intent:find("Do not repeat", 1, true), nil, "and not the constraint that invited rewording")
H.ok(built2.intent:find("not a file", 1, true) ~= nil, "and says a feature is not a file")

-- THE LIST IS CAPPED, AND SAYS SO. It grew with the map, which put three
-- hundred names into every request. Silent truncation would read as "these
-- are all of them" — the one thing it must not mean.
local many = {}
for i = 1, 90 do
  many[#many + 1] = ("feature capability number %d"):format(i)
  many[#many + 1] = "  module src/f.lua"
end
local big = recover.build(map.parse(many), { "src/z.lua" }, { module = true }, {}, { "lua" })
H.ok(big.intent:find("40 most recent of 90", 1, true) ~= nil, "the cap is stated with both numbers")
H.ok(big.intent:find("capability number 90", 1, true) ~= nil, "the newest is shown")
H.eq(big.intent:find("capability number 1\n", 1, true), nil, "the oldest is dropped, not hidden")

-- RE-OPENING MUST NOT READ AS REPETITION. Naming a feature again is how a
-- later batch adds to what an earlier one wrote, and the parser has always
-- read those blocks as one feature. The buffer did not: four batches that
-- each added to `Inspect how the library maintains itself` left four
-- `feature` lines with that name, so fourteen capabilities were written
-- across twenty-eight headers and read as a page of duplicates. The
-- fragmentation the re-open move fixed had become repetition.
local K = { route = true, module = true }
local folded_lines, folded = recover.consolidate({
  "feature Work through a checklist",
  "  route c/[slug]",
  "    the runnable page",
  "",
  "feature Fetch as JSON",
  "  module src/x.json.ts",
  "",
  "feature Work through a checklist",
  "  module src/lib/run.js",
  "  route c/[slug]",
  "",
}, K)
H.eq(folded, 1, "one duplicate header is absorbed")
local text = table.concat(folded_lines, "\n")
local headers = 0
for _ in text:gmatch("\nfeature ") do
  headers = headers + 1
end
H.eq(headers + 1, 2, "two features, written once each")
H.ok(text:find("module src/lib/run.js", 1, true) ~= nil, "the later block's member moved up")
H.ok(text:find("the runnable page", 1, true) ~= nil, "and the first block's intent line stayed with its member")

-- A member written twice is one claim, not two — two batches naming the
-- same route agree with each other rather than disagreeing.
local _, n = text:gsub("route c/%[slug%]", "")
H.eq(n, 1, "a repeated member is kept once")

-- ORDER SURVIVES. Features keep the order they were first written in, so a
-- map does not reshuffle under a reader between batches.
H.eq(folded_lines[1], "feature Work through a checklist", "the first feature is still first")

-- A FEATURE WRITTEN ONCE IS RETURNED EXACTLY AS IT WAS. Its blank lines are
-- someone's layout, and consolidating is not a license to reformat.
local untouched = {
  "feature Only ever written once",
  "  Prose about it.",
  "",
  "  module src/a.lua",
}
local same, none = recover.consolidate(untouched, K)
H.eq(none, 0, "nothing to fold")
H.eq(table.concat(same, "\n"), table.concat(untouched, "\n") .. "\n", "and the block comes back as written")

-- Prose above the first feature is not inside any feature and stays put.
local led = recover.consolidate({ "-- a note", "", "feature a", "  module x.lua" }, K)
H.eq(led[1], "-- a note", "a leading comment keeps its place")

H.done("recover_spec PASS")
