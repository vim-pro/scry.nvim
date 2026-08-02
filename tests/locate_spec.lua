-- Where a claim points. The ORDER is the whole subject: evidence beats the
-- claim's own text, because evidence is a place an engine actually looked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local locate = require("scry.locate")
local glass = require("scry.glass")

-- A project we can check for real.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
for _, f in ipairs({ "auth.lua", "store.lua", "logging.lua" }) do
  vim.fn.writefile(vim.fn.readfile(H.fixture .. "/lua/" .. f), work .. "/lua/" .. f)
end
vim.fn.mkdir(work .. "/.scry", "p")
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/map.scry"), work .. "/.scry/map.scry")
require("scry").setup({ holdout_path = work .. "/holdout-test.scry" })
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/holdout.scry"), work .. "/holdout-test.scry")

-- 1) A `contains` claim lands on the DEFINITION, not line 1 and not the
-- first textual mention. The line comes from the same treesitter query that
-- decides `✓ defined`, so "where" can never disagree with "whether".
local claim = { kind = "def", target = "lua/auth.lua:create_session", feature = "f" }
local t = locate.target(claim, nil, work)
H.eq(t.path, "lua/auth.lua", "the claim's own file")
H.eq(t.why, "definition", "resolved as a definition")
local src = vim.fn.readfile(work .. "/lua/auth.lua")
H.ok(
  src[t.lnum]:find("create_session", 1, true) ~= nil,
  ("line %d is the definition, not a guess: %q"):format(t.lnum, src[t.lnum] or "")
)

-- 2) EVIDENCE WINS. Given a verdict carrying a line an engine actually
-- found, the jump goes there rather than to the claim's own file — that is
-- the case where scry knows something the claim text does not.
local with_evidence = locate.target(
  claim,
  { status = "backed", evidence = { { path = "lua/store.lua", lnum = 7, text = "store.put(...)" } } },
  work
)
H.eq(with_evidence.path, "lua/store.lua", "evidence outranks the claim's path")
H.eq(with_evidence.lnum, 7, "and carries its line")
H.eq(with_evidence.why, "evidence", "and says so")

-- 3) Run output is evidence with no place in it (lnum 0). It must not be
-- mistaken for a location — falling back to the file is honest, jumping to
-- line 0 is not.
local runout = locate.target(claim, { status = "backed", evidence = { { path = "x", lnum = 0, text = "ok" } } }, work)
H.eq(runout.path, "lua/auth.lua", "lnum 0 is not a destination")
H.eq(runout.why, "definition", "so it falls back to the claim")

-- 4) A file-level claim has no symbol to find: line 1, honestly labeled.
local filelevel = locate.target({ kind = "def", target = "lua/store.lua", feature = "f" }, nil, work)
H.eq(filelevel.path, "lua/store.lua", "the file itself")
H.eq(filelevel.lnum, 1, "line 1")
H.eq(filelevel.why, "file", "not claiming to be a definition")

-- 5) NOTHING IS INVENTED. A holding prohibition names a pattern, not a
-- place; with no evidence there is nowhere to go and the answer is nil.
H.eq(locate.target({ kind = "never", target = "print%(", feature = "f" }, nil, work), nil, "a clean never has no destination")
H.eq(locate.target({ kind = "calls", target = "store.lua::put", feature = "f" }, nil, work), nil, "nor does an unevidenced calls")

-- ...but a VIOLATED prohibition is the most useful jump scry has.
local violated = locate.target(
  { kind = "never", target = "print%(", feature = "f" },
  { status = "violated", evidence = { { path = "lua/logging.lua", lnum = 3, text = "print(x)" } } },
  work
)
H.eq(violated.path, "lua/logging.lua", "a violation jumps to the violation")
H.eq(violated.lnum, 3, "at its line")

-- 6) A symbol that is not defined does not fabricate a line.
local absent = locate.target({ kind = "def", target = "lua/auth.lua:no_such_fn", feature = "f" }, nil, work)
H.eq(absent.lnum, 1, "an absent symbol falls back to the file")
H.eq(absent.why, "file", "and does not claim to have found a definition")

-- 7) FOLDING HAS TWO LEVELS, because the map has two altitudes: what a
-- feature IS (its name and the sentence under it) and what it is MADE OF.
--
-- That is the whole reason the default view can show a description at all.
-- With one level per feature, everything under the name was inside the fold,
-- so the only closed view was a stack of bare titles — and the titles are
-- the part a reader can already guess. Splitting it means `zM` still gives
-- that scan, the default gives titles AND their sentences, and `zR` gives
-- the files. The outline is a zoom, and vim already had the control for it.
--
-- Lines above the first feature belong to no fold — a stale header or a
-- drafting block must not be swallowed.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "-- a drafting block",
  "feature one",
  "  prose",
  "  contains",
  "    a.lua:x",
  "",
  "feature two",
  "  prose",
  "  never",
  "    print%(",
  "",
  "    io%.write",
})
vim.api.nvim_win_set_buf(0, buf)
H.eq(glass.foldexpr(1), "0", "above the first feature: no fold")
H.eq(glass.foldexpr(2), ">1", "a feature opens a fold")
H.eq(glass.foldexpr(3), "1", "the sentence saying what it is stays with it")
H.eq(glass.foldexpr(4), ">2", "and its members open a second, deeper one")
H.eq(glass.foldexpr(5), "2", "which the rest of the run continues")
H.eq(glass.foldexpr(7), ">1", "the next feature starts its own")

-- THE BLANK BEFORE A FEATURE IS THE AUTHOR'S, and it is the only blank a
-- reader put there on purpose. Taking the level of the line above it — the
-- rule for every other blank — swallowed it into the member fold, so it
-- vanished whenever the members were closed and the default view went back
-- to features stacked with nothing between them: the render deleting the
-- layout of the file it is showing.
H.eq(glass.foldexpr(6), "1", "the blank before a feature stays out of the member fold")

-- Every other blank takes the level above it. A paragraph break inside a
-- never-block is layout, not a terminator — the parser's rule, and a fold
-- that disagreed with it would hide half a prohibition.
H.eq(glass.foldexpr(11), "=", "a blank inside a member run does not cut the run in two")
H.eq(glass.foldexpr(12), "2", "so the pattern after it is still in the same fold")

H.done("locate_spec PASS")
