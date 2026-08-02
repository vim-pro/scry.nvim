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

-- 7) FOLDING is per feature, and lines above the first feature belong to no
-- fold — a stale header or a drafting block must not be swallowed.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "-- a drafting block",
  "feature one",
  "  prose",
  "  contains",
  "    a.lua:x",
  "feature two",
  "  prose",
})
vim.api.nvim_win_set_buf(0, buf)
H.eq(glass.foldexpr(1), "0", "above the first feature: no fold")
H.eq(glass.foldexpr(2), ">1", "a feature opens a fold")
H.eq(glass.foldexpr(4), "1", "its body is inside")
H.eq(glass.foldexpr(6), ">1", "the next feature starts its own")
H.eq(glass.foldexpr(7), "1", "and takes the rest")

H.done("locate_spec PASS")
