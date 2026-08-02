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

H.done("compose_spec PASS")
