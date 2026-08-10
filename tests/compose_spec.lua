-- Programming at the altitude of a capability: one intent, cast across
-- every file a feature is made of.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local compose = require("scry.compose")
local mapmod = require("scry.map")

local KINDS = require("scry.kinds").all({
  kinds = { route = { path = "src/pages/{name}.astro" }, endpoint = { path = "src/pages/api/{name}.ts" } },
})

local FEATURE = mapmod.parse({
  "feature Tailor a checklist to your own situation",
  "  Describe your circumstances and the compiler selects from vetted steps.",
  "  endpoint compile",
  "    selects and lightly adapts canonical items",
  "    remove the legacy csv branch",
  "  route copy",
  "  route print",
}, KINDS).features[1]

-- Only two of the three exist on disk.
local ON_DISK = {
  ["src/pages/api/compile.ts"] = { "export function compile() {}" },
  ["src/pages/copy.astro"] = { "<h1>copy</h1>" },
}
local function read(path)
  return ON_DISK[path]
end

-- 1) THE REQUEST CARRIES THE WHOLE CAPABILITY, which is the entire reason
-- this is one cast rather than one per file. A page and the endpoint it
-- posts to have to agree, and no request that sees only one of them can
-- make them agree.
local req = compose.request("/proj", FEATURE, "add a PDF export", KINDS, read)
H.eq(#req.files, 3, "every member that names a file is in the cast")
H.ok(req.user:find("Tailor a checklist", 1, true) ~= nil, "the feature is named")
H.ok(req.user:find("Describe your circumstances", 1, true) ~= nil, "its prose rides along")
H.ok(req.user:find("add a PDF export", 1, true) ~= nil, "and the intent")
H.ok(req.user:find("export function compile", 1, true) ~= nil, "an existing file's contents are shown")
H.ok(req.user:find("<h1>copy</h1>", 1, true) ~= nil, "all of them, not just the first")
H.ok(req.user:find("selects and lightly adapts", 1, true) ~= nil, "a member's own note is shown too")
-- ALL of a member's notes. A plan (|scry-plan|) writes what should happen in
-- a file as these lines, and a cast that reads only the first line of its
-- own instructions builds half the plan.
H.ok(req.user:find("remove the legacy csv branch", 1, true) ~= nil, "every note line, not just the first")

-- A MEMBER NAMES ITS FILE BEFORE THE FILE EXISTS. `route print` resolves
-- through its kind's probe whether or not anything is there, so adding a
-- capability and changing one are the same verb: absent members are files to
-- create.
H.ok(req.user:find("src/pages/print.astro", 1, true) ~= nil, "an absent member still names its file")
H.ok(req.user:find("DOES NOT EXIST YET", 1, true) ~= nil, "and is marked as one to create")

-- A member that names no file cannot be cast across — a `never` is a
-- pattern and a grep-probed kind can match anywhere.
local vague = mapmod.parse({ "feature f", "  never print%(" }, KINDS).features[1]
H.eq(#compose.request("/proj", vague, "x", KINDS, read).files, 0, "a prohibition is not a place to edit")

-- 1b) THE REST OF THE PRODUCT RIDES ALONG, READ-ONLY. A cast that knows
-- only its own files invents the rest: a one-member feature came back
-- requiring a module that does not exist. With the map passed, the request
-- carries the other features for orientation and the NAMES their existing
-- files define — enough to call into, nothing to rewrite.
local WHOLE = mapmod.parse({
  "feature Tailor a checklist to your own situation",
  "  endpoint compile",
  "",
  "feature keep the store honest",
  "  The store reads and writes every list.",
  "  def src/lib/store.lua:put",
  "  exercises",
  "    tests/store_spec.lua:round trip",
}, KINDS)
ON_DISK["src/lib/store.lua"] = { "local M = {}", "function M.put(x) end", "function M.get(k) end", "return M" }
local target = WHOLE.features[1]
local ctx = compose.request("/proj", target, "add a PDF export", KINDS, read, WHOLE)
H.ok(ctx.user:find("THE REST OF THE PRODUCT", 1, true) ~= nil, "the other features are shown")
H.ok(ctx.user:find("feature keep the store honest", 1, true) ~= nil, "by name")
H.ok(ctx.user:find("The store reads and writes", 1, true) ~= nil, "with their prose")
H.ok(ctx.user:find("src/lib/store.lua: M.put, M.get", 1, true) ~= nil, "an outside file contributes its defined names")
H.eq(ctx.user:find("tests/store_spec%.lua"), nil, "another feature's spec stays out of the request entirely")
H.eq(ctx.user:find("function M%.get"), nil, "outside files contribute names, never contents")
H.eq(#ctx.files, 1, "and the emittable set is still only this feature's own files")

-- 2) THE PARSER. Whole files, never diffs — there is no hunk to misapply.
local parsed = compose.parse(table.concat({
  "<<<FILE src/pages/copy.astro",
  "<h1>copy</h1>",
  "<a href=/print>print</a>",
  "FILE>>>",
  "<<<FILE src/pages/print.astro",
  "<h1>print</h1>",
  "FILE>>>",
}, "\n"))
H.eq(#parsed, 2, "both files come back")
H.eq(parsed[1].path, "src/pages/copy.astro", "with their paths")
H.eq(#parsed[1].lines, 2, "and their whole contents")
H.eq(parsed[2].lines[1], "<h1>print</h1>", "including the created one")

-- A TRUNCATED BLOCK IS DROPPED, not half-applied. A cast that runs out of
-- output tokens mid-file is the common failure, and writing half a file
-- into a buffer is worse than writing none of it.
local cut = compose.parse(table.concat({
  "<<<FILE a.ts",
  "line one",
  "FILE>>>",
  "<<<FILE b.ts",
  "line one of a file that never end",
}, "\n"))
H.eq(#cut, 1, "the closed block survives")
H.eq(cut[1].path, "a.ts", "and it is the right one")

-- Prose around the blocks is ignored rather than fatal.
local chatty = compose.parse("Sure! Here you go:\n\n<<<FILE a.ts\nx\nFILE>>>\n\nLet me know!")
H.eq(#chatty, 1, "commentary outside the blocks does not break it")
H.eq(chatty[1].lines[1], "x", "and does not leak into one")
H.eq(#compose.parse(""), 0, "an empty result is no files, not an error")
H.eq(#compose.parse("I could not do that."), 0, "and neither is a refusal")

-- 3) A CAST MAY ONLY EDIT WHAT IT WAS SHOWN. A path the model invented is a
-- path nobody named — writing it would make the map a liar about what
-- the feature is made of, and would edit files the reader never put in
-- scope.
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/src/pages/api", "p")
vim.fn.writefile({ "old" }, proj .. "/src/pages/copy.astro")
local allowed = { ["src/pages/copy.astro"] = true, ["src/pages/print.astro"] = true }
local res = compose.apply(proj, {
  { path = "src/pages/copy.astro", lines = { "new" } },
  { path = "src/pages/print.astro", lines = { "fresh" } },
  { path = "src/lib/secrets.js", lines = { "not yours" } },
}, allowed)
H.eq(#res.changed, 1, "an existing named file is changed")
H.eq(res.changed[1], "src/pages/copy.astro", "and named")
H.eq(#res.created, 1, "an absent named file is created")
H.eq(res.created[1], "src/pages/print.astro", "and named")
H.eq(#res.refused, 1, "a file nobody named is refused")
H.eq(res.refused[1], "src/lib/secrets.js", "and named, rather than dropped quietly")

-- 4) NOTHING TOUCHES THE DISK. The result lands in buffers, modified and
-- unsaved — which is exactly the state you would be in had you typed it
-- yourself. Review is then vim's: `u`, `:w`, `:e!`, `:diffthis`. Inventing
-- a review UI here would be worse than the one already in your hands.
H.eq(table.concat(vim.fn.readfile(proj .. "/src/pages/copy.astro"), "\n"), "old", "the file on disk is untouched")
H.eq(vim.fn.filereadable(proj .. "/src/pages/print.astro"), 0, "and a created file is not written either")

local buf = vim.fn.bufadd(proj .. "/src/pages/copy.astro")
vim.fn.bufload(buf)
H.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "new", "the change is in the buffer")
H.eq(vim.bo[buf].modified, true, "which is modified and unsaved, as if you had typed it")

-- The refused path was never even opened.
H.eq(vim.fn.bufexists(proj .. "/src/lib/secrets.js"), 0, "a refused file is not loaded, let alone written")

-- 5) THE CAST LANDS YOU IN THE CHANGE. Measured by running it: the old
-- ending printed a summary longer than the window, so every SUCCESSFUL cast
-- finished at a `Press ENTER` prompt and then left you typing `:b` with
-- paths you had to recall — eight steps to answer "did it do what I asked",
-- on the one gesture that is supposed to feel like `d2w`.
--
-- The list is the answer instead. Changes go where changes go in this stack,
-- and then every key is one you already have: `]q` walks it, `u` undoes a
-- file, `:w` keeps one.
local seeded = require("scry.compose")
local fake_root = vim.fn.tempname()
vim.fn.mkdir(fake_root, "p")
vim.fn.writefile({ "old" }, fake_root .. "/a.ts")
vim.fn.setqflist({}, "r") -- start clean so the assertions are about this cast

local applied = seeded.apply(fake_root, {
  { path = "a.ts", lines = { "new" } },
  { path = "b.ts", lines = { "fresh" } },
}, { ["a.ts"] = true, ["b.ts"] = true })
seeded._seed(fake_root, "add a PDF export", applied)

local qf = vim.fn.getqflist({ title = 1, items = 1 })
H.eq(#qf.items, 2, "every file the cast touched is in the list")
H.ok(qf.title:find("add a PDF export", 1, true) ~= nil, "titled with the intent, so the list says what it is")
local texts = {}
for _, item in ipairs(qf.items) do
  texts[#texts + 1] = item.text
end
table.sort(texts)
H.eq(table.concat(texts, ","), "changed,created", "and says which are new, because that changes how you read them")

-- 6) A CAST CAN BE TAKEN BACK. An operator you cannot reverse is not an
-- operator, it is a commitment — and `:e!` once per file, from a list of
-- paths you had to remember, meant the real undo was git.
H.eq(vim.bo[vim.fn.bufnr(fake_root .. "/a.ts")].modified, true, "the changed file is modified before")
seeded.discard()
local reverted = vim.fn.bufnr(fake_root .. "/a.ts")
H.eq(vim.api.nvim_buf_get_lines(reverted, 0, -1, false)[1], "old", "an edited file goes back to what is on disk")
H.eq(vim.bo[reverted].modified, false, "and stops being modified")
-- A file the cast INVENTED has nothing on disk to go back to, so taking it
-- back means the buffer goes rather than reloading from nothing.
H.eq(vim.fn.bufexists(fake_root .. "/b.ts"), 0, "a created file is gone entirely")
H.eq(vim.fn.filereadable(fake_root .. "/b.ts"), 0, "and never reached the disk in the first place")

-- ONCE YOU SAVE, IT IS YOURS. Reverting a file already written is git's job,
-- and doing it behind someone's back would be the most destructive thing
-- here. Discard says which files it could not take back rather than
-- reporting a clean sweep it did not perform.
vim.fn.writefile({ "old" }, fake_root .. "/c.ts")
seeded.apply(fake_root, { { path = "c.ts", lines = { "cast wrote this" } } }, { ["c.ts"] = true })
local saved = vim.fn.bufnr(fake_root .. "/c.ts")
vim.api.nvim_buf_call(saved, function()
  vim.cmd("silent write")
end)
local told
local restore = vim.notify
vim.notify = function(m)
  told = m
end
seeded.discard()
vim.notify = restore
H.eq(vim.fn.readfile(fake_root .. "/c.ts")[1], "cast wrote this", "a saved file is left exactly alone")
H.ok(told and told:find("c.ts", 1, true) ~= nil, "and named as one discard could not take back: " .. tostring(told))
H.ok(told:find("git", 1, true) ~= nil, "with the tool that can")

-- 5) REVIEW: the diff, with the map still in the room.
--
-- The first review was `cfirst`: line ONE of the first changed file. On a
-- 2,200-line stylesheet whose change sat at line 2081, that was an unmarked
-- buffer, nothing saying where the change was, and the plan — the reason you
-- were there — a buffer away. The review is a tab now: the glass on top,
-- full width, and below it what is on disk against what the cast wrote.
local review_root = vim.fn.tempname()
vim.fn.mkdir(review_root, "p")
vim.fn.writefile({ "old line one", "old line two" }, review_root .. "/a.css")
local a_buf = vim.fn.bufadd(review_root .. "/a.css")
vim.fn.bufload(a_buf)
vim.api.nvim_buf_set_lines(a_buf, 0, -1, false, { "old line one", "NEW line two" })
local b_buf = vim.fn.bufadd(review_root .. "/b.css")
vim.fn.bufload(b_buf)
vim.api.nvim_buf_set_lines(b_buf, 0, -1, false, { "a created file" })

local fake_glass = vim.api.nvim_create_buf(true, true)
local tabs_before = #vim.api.nvim_list_tabpages()
compose.review(review_root, fake_glass, {
  { path = "a.css", created = false },
  { path = "b.css", created = true },
})

H.eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "the review is its own tab — closing it is leaving")
local wins = vim.api.nvim_tabpage_list_wins(0)
H.eq(#wins, 3, "three windows: the glass, and the two sides of the diff")

local top, diffed = nil, {}
for _, win in ipairs(wins) do
  if vim.api.nvim_win_get_buf(win) == fake_glass then
    top = win
  elseif vim.wo[win].diff then
    diffed[#diffed + 1] = win
  end
end
H.ok(top ~= nil, "the glass is one of them — the plan stays in the room")
H.eq(vim.api.nvim_win_get_width(top), vim.o.columns, "and it spans the full width, above both panes")
H.eq(#diffed, 2, "the other two are in diff mode")

-- The cursor is IN the change, not at line 1 of the file. This is the whole
-- complaint the review exists to answer.
H.eq(vim.api.nvim_get_current_buf(), a_buf, "the cast's side is focused")
H.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "with the cursor on the first changed line, not line one")

-- The disk side is what `:w` would overwrite, and it is not editable — it is
-- the past, shown for comparison.
local disk_buf
for _, win in ipairs(diffed) do
  local b = vim.api.nvim_win_get_buf(win)
  if b ~= a_buf then
    disk_buf = b
  end
end
H.eq(vim.api.nvim_buf_get_lines(disk_buf, 0, -1, false)[2], "old line two", "the disk side shows what is on disk")
H.eq(vim.bo[disk_buf].modifiable, false, "and cannot be edited — it is the past")

-- ]q walks the files WITHIN the layout: both panes move together, and a
-- created file diffs against nothing, which shows the whole file as new —
-- the truth.
local map_found = false
for _, m in ipairs(vim.api.nvim_buf_get_keymap(a_buf, "n")) do
  if m.lhs == "]q" then
    map_found = true
  end
end
H.ok(map_found, "]q is bound in the review's panes, and only there")
-- The cast's side is already the current window, which is where a reader
-- pressing ]q actually is. (Not nvim_buf_call: that wraps the keys in a
-- temporary window context and restores it afterward, un-doing the very
-- window switch the motion performs.)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("]q", true, false, true), "x", false)
H.eq(vim.api.nvim_get_current_buf(), b_buf, "]q moves both panes to the next file")
vim.cmd("tabclose")

H.done("compose_spec PASS")
