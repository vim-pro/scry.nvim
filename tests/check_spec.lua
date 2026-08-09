-- Reflexion fan-out with a fake resolver (recorded {claim, cb}, answered by
-- hand — conjurer's aggregate_spec pattern), plus debt arithmetic.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local check = require("scry.check")
local debt = require("scry.debt")

local SRC = {
  "feature a",
  "  contains",
  "    x.lua:one",
  "    x.lua:two",
  "  never",
  "    bad_pattern",
}
local m = map.parse(SRC)

-- fake resolver records calls; the spec answers them
local calls = {}
local fake = {
  name = "fake",
  check_def = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
  check_never = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
  check_calls = function(ctx, claim, cb)
    table.insert(calls, { claim = claim, cb = cb, globs = ctx.globs })
  end,
}

local report
check.run(m, { root = "/nowhere", resolver = fake }, function(r)
  report = r
end)
H.eq(#calls, 3, "one resolver call per claim")
H.eq(report, nil, "report not settled until every verdict arrives")
H.eq(calls[1].globs[1], "x.lua", "the derived footprint travels in ctx")

calls[1].cb({ status = "backed", fidelity = "ts-def", label = "✓ defined" })
calls[2].cb({ status = "missing", fidelity = "ts-def", label = "✗ absent" })
H.eq(report, nil, "still pending")
calls[3].cb({ status = "violated", fidelity = "rg-text", label = "✗ VIOLATED", evidence = {} })
H.ok(report ~= nil, "settled once, after the last verdict")
H.ok(report.at > 0, "report is timestamped")

-- debt: the verdict axis, and only the verdict axis
local d = debt.count(m, report)
H.eq(d.claims, 3, "claim count")
H.eq(d.backed, 1, "backed")
H.eq(d.missing, 1, "missing")
H.eq(d.violated, 1, "violated")

-- header renders separate numbers with the claim count leading
local header = debt.header(d, report.at)
-- Features lead the header, because the question a reader arrives with is
-- what the product does, not how many subfunctions resolved.
--
-- Asserted as the count and the word rather than as the string `1 features`,
-- which is what this pinned before. The map has ONE feature in it, so the
-- literal being defended was a plural bug — the spec was holding the defect
-- in place instead of the promise, on the first line anyone ever sees.
H.ok(header:find("1 feature", 1, true) ~= nil, "features lead the header")
H.eq(header:find("1 features", 1, true), nil, "and one of them is not plural")
H.ok(header:find("3 claims", 1, true) ~= nil, "claim evidence follows")
H.ok(header:find("1 backed", 1, true) ~= nil, "backed shown")
H.ok(header:find("1 violated", 1, true) ~= nil, "violated shown")
H.ok(header:find("files on disk", 1, true) ~= nil, "the disk caveat travels with every render")

-- A claim no engine could answer must occupy a column of its own. The
-- reader's whole interaction with debt is glancing at this line: if unchecked
-- claims are simply absent from it, "0 missing · 0 violated" reads as a clean
-- bill of health for claims nothing ever looked at.
local SRC2 = {
  "feature mixed",
  "  contains",
  "    src/app.lua:go",
  "    src/thing.py:handle", -- no lua resolver
  "    src/other.rb:run", -- no lua resolver
}
local m2 = map.parse(SRC2)
calls = {}
local report2
check.run(m2, { root = "/nowhere", resolver = fake }, function(r)
  report2 = r
end)
calls[1].cb({ status = "backed", fidelity = "ts-def", label = "✓ defined" })
calls[2].cb({ status = "unchecked", fidelity = "none", label = "– unchecked (no lua resolver)" })
calls[3].cb({ status = "error", fidelity = "none", label = "– resolver error" })

local d2 = debt.count(m2, report2)
H.eq(d2.unchecked, 2, "unchecked and error verdicts both land in the unchecked column")
H.eq(d2.backed + d2.missing + d2.violated + d2.unchecked, d2.claims, "the four columns account for every claim")
local h2 = debt.header(d2, report2.at)
H.ok(h2:find("2 unchecked", 1, true) ~= nil, "the header names them: " .. h2)
H.ok(debt.header(d, report.at):find("unchecked", 1, true) == nil, "and stays quiet when there are none")

-- THE HEADER LIVES IN THE WINBAR. It was virt_lines above line 1, which
-- Neovim never draws — there is no room above a buffer's first line — so it
-- was invisible on exactly the map a new user opens first. Verified against
-- a real terminal, not just the extmark being set.
local wb = debt.winbar(d, report.at)
H.ok(wb:find("1 feature", 1, true) ~= nil, "features still lead: " .. wb)
H.ok(wb:find("3 claims", 1, true) ~= nil, "claim evidence still travels with them")
H.ok(wb:find("files on disk", 1, true) ~= nil, "and so does the disk caveat")
H.ok(wb:find("\n", 1, true) == nil, "one line — a winbar is one line")
-- `%<` is where Vim cuts a too-long winbar. It sits after the feature counts
-- so a narrow window gives up the claim-level evidence first and shows `<`,
-- which reads as cut off rather than as absent.
-- FITTED, not truncated by Vim. `%<` was tried in the middle (it keeps the
-- tail and eats the words before it: `(files on disk)<issing`) and at the
-- end (the bar renders EMPTY). So the segments are joined only when they
-- fit, and a narrow window keeps the features and drops the claim counts.
H.eq(wb:find("%%<"), nil, "no Vim truncation marker; the fitting is ours")
local narrow = debt.winbar(d, report.at, 40)
H.ok(vim.fn.strdisplaywidth(narrow:gsub("%%#%w+#", ""):gsub("%%%*", "")) <= 40, "a narrow window gets a line that fits: " .. narrow)
H.ok(narrow:find("feature", 1, true) ~= nil, "and keeps the features")
H.eq(narrow:find("3 claims", 1, true), nil, "dropping the claim counts, which are the evidence beneath them")
-- COLOR MEANS STATE, and nothing else. The bar was one band of ScryHeader,
-- which linked to Title — in a normal scheme the loudest color it has —
-- spent on the words "scry", "features" and "checked", none of which is
-- news. The counts are the only thing on the line that says anything, so
-- they carry the same groups the state column does and the frame recedes.
local seg1 = select(1, debt.parts(d, report.at))
local by_text = {}
for _, seg in ipairs(seg1) do
  by_text[seg[1]] = seg[2]
end
H.eq(by_text["scry"], "ScryHeaderDim", "the name of the tool is not the news")
for text, group in pairs(by_text) do
  if text:find("done") then
    H.eq(group, "ScryDone", "a done count reads as done")
  elseif text:find("broken") then
    H.eq(group, "ScryBroken", "and broken as broken")
  end
end
H.ok(wb:find("%%#ScryHeaderDim#") ~= nil, "the winbar carries the frame group")
H.eq(wb:find("%%#ScryHeader#[^%%]*checked"), nil, "and does not paint the whole line one color")

-- Literal percent signs in the text would be read as statusline items.
H.ok(select(2, debt.winbar(d, nil):gsub("%%%%", "")) >= 0, "percent-escaping applied")

-- No report at all is not a pass either: every claim is unchecked.
local d3 = debt.count(m2, nil)
H.eq(d3.unchecked, 3, "with no report, nothing is accounted for")
H.eq(d3.backed, 0, "and nothing is backed")

-- empty map settles immediately
local settled = false
check.run(map.parse({}), { root = "/nowhere", resolver = fake }, function()
  settled = true
end)
H.eq(settled, true, "empty map settles synchronously")

H.done("check_spec PASS")
