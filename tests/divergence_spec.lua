-- Divergence: reflexion's third verdict.
--
-- The assertion this file exists for is the one that makes a feature list
-- honest: a map whose every feature is DONE can still describe a fraction
-- of the product, and without divergence nothing on the page would say so.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local div = require("scry.divergence")
local debt = require("scry.debt")

if vim.fn.executable("rg") ~= 1 then
  H.fail("ripgrep is required for divergence (and this spec)")
end

-- Six source files; the map will describe two of them.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua/auth", "p")
vim.fn.mkdir(work .. "/lua/billing", "p")
vim.fn.mkdir(work .. "/tests", "p")
vim.fn.mkdir(work .. "/.scry", "p")
local function write(rel, lines)
  vim.fn.writefile(lines, work .. "/" .. rel)
end
write("lua/auth/reset.lua", { "local M = {}", "function M.request_reset() end", "return M" })
write("lua/auth/tokens.lua", { "local M = {}", "function M.mint() end", "return M" })
write("lua/billing/charge.lua", { "local M = {}", "function M.charge() end", "return M" })
write("lua/billing/refund.lua", { "local M = {}", "function M.refund() end", "return M" })
write("tests/reset_spec.lua", { "os.exit(0)" })
write("tests/orphan_spec.lua", { "os.exit(0)" })

local MAP = {
  "feature a user can reset their password",
  "  contains",
  "    lua/auth/reset.lua:request_reset",
  "  exercises",
  "    tests/reset_spec.lua",
}
write(".scry/map.scry", MAP)
local m = map.parse(MAP)
local config = { map_path = ".scry/map.scry", holdout_path = "", sources = {} }

-- 1) the claimed files are exactly the union of footprints; everything else
-- is divergence
local unclaimed, total = div.unclaimed(work, m, config)
table.sort(unclaimed)
H.eq(total, 6, "six claimable files seen")
H.eq(#unclaimed, 4, "four of them are claimed by no feature")
H.eq(unclaimed[1], "lua/auth/tokens.lua", "a sibling in a described directory is still unclaimed")
H.eq(unclaimed[2], "lua/billing/charge.lua", "an undescribed area shows up whole")
H.eq(unclaimed[3], "lua/billing/refund.lua", "...every file of it")
H.eq(unclaimed[4], "tests/orphan_spec.lua", "a spec no feature exercises is unclaimed too")
H.ok(not vim.tbl_contains(unclaimed, "lua/auth/reset.lua"), "a named file is claimed")
H.ok(not vim.tbl_contains(unclaimed, "tests/reset_spec.lua"), "so is an exercised spec")

-- 2) SCRY'S OWN BOOKKEEPING IS NOT PRODUCT. A fresh map must never open by
-- accusing you of failing to describe the map.
H.ok(not vim.tbl_contains(unclaimed, ".scry/map.scry"), "the map does not count against itself")
local in_repo = { map_path = ".scry/map.scry", holdout_path = "holdout.scry", sources = {} }
write("holdout.scry", { "feature x", "  never", "    nope" })
local u2 = div.unclaimed(work, m, in_repo)
H.ok(not vim.tbl_contains(u2, "holdout.scry"), "nor does an in-repo holdout")
-- ...and remove it again, so this check does not change the counts below
vim.fn.delete(work .. "/holdout.scry")

-- 3) THE POINT. Every feature done, and the map still describes a third of
-- the product. Divergence is the only thing on the page that says so — the
-- feature axis is about the claims you wrote, and it cannot see what you
-- never wrote a claim about.
local all_done = { at = os.time(), verdicts = {} }
for _, c in ipairs(m.claims) do
  all_done.verdicts[require("scry.map").claim_id(c)] = { status = "backed", label = "✓ defined" }
end
local d = debt.count(m, all_done, work)
H.eq(d.todo, 0, "nothing outstanding, by the feature axis alone")
H.eq(d.unclaimed, 4, "yet four files are described by nothing")
local header = debt.header(d, all_done.at)
local first = vim.split(header, "\n")[1]
H.ok(first:find("4", 1, true) ~= nil, "so the header says it on the line the reader scans: " .. first)
H.ok(
  first:find("undescribed", 1, true) ~= nil or first:find("unclaimed", 1, true) ~= nil,
  "and says what the number is about"
)
-- WITH ITS DENOMINATOR. "4 undescribed" reads as alarming against six files
-- and as nearly finished against four thousand, and the header gave no way
-- to tell which.
H.ok(first:find("of 6", 1, true) ~= nil, "against the number of files there are")

-- 4) `sources` narrows what counts, for repos where everything is noise
local lua_only = { map_path = ".scry/map.scry", holdout_path = "", sources = { "lua/**/*.lua" } }
local u3 = div.unclaimed(work, m, lua_only)
H.eq(#u3, 3, "narrowing to lua/ drops the orphan spec")
H.ok(not vim.tbl_contains(u3, "tests/orphan_spec.lua"), "specifically that one")

-- 5) a map claiming everything reports nothing
local FULL = {
  "feature everything",
  "  contains",
  "    lua/auth/reset.lua:request_reset",
  "    lua/auth/tokens.lua:mint",
  "    lua/billing/charge.lua:charge",
  "    lua/billing/refund.lua:refund",
  "  exercises",
  "    tests/reset_spec.lua",
  "    tests/orphan_spec.lua",
}
local u4, t4 = div.unclaimed(work, map.parse(FULL), config)
H.eq(#u4, 0, "a map that names every file has no divergence")
H.eq(t4, 6, "and still sees all six")

-- 6) divergence is best-effort: a root that has gone away must not take the
-- header down with it
local gone = debt.count(m, all_done, work .. "/does-not-exist")
H.eq(gone.unclaimed, 0, "a missing root yields no divergence rather than an error")
H.eq(gone.features, 1, "and the rest of the header still computes")


-- SCALE IS NOT SPEED. Measured on a twenty-thousand-file project,
-- divergence takes 24ms and the check 59ms — what fails is the REPORT.
-- Eighteen thousand unclaimed files is the same wall of detail the altitude
-- work was about, one level up, and a quickfix window with eighteen
-- thousand rows is a thing you close rather than a thing you work.
local d = require("scry.divergence")
local many = {}
for p = 0, 199 do
  for f = 1, 94 do
    many[#many + 1] = ("packages/pkg%03d/src/mod%03d.lua"):format(p, f)
  end
end
H.eq(#many, 18800, "the shape of a real large repository")
local rolled = d.rollup(many, 200)
H.ok(#rolled <= 200, "rolled up to something a reader can hold: " .. #rolled .. " rows")
H.ok(rolled[1].count > 1, "each row stands for many files")
H.ok(rolled[1].sample:find(rolled[1].path, 1, true) == 1, "and names a real file to jump to")
local sum = 0
for _, g in ipairs(rolled) do
  sum = sum + g.count
end
H.eq(sum, #many, "every file is accounted for, none dropped in the grouping")

-- A SMALL PROJECT IS UNCHANGED. Grouping is what you do when a list stops
-- being readable, not a thing to do to three files.
local few = { "src/lib/db.js", "src/lib/run.js", "src/pages/about.astro" }
local small = d.rollup(few, 200)
H.eq(#small, 3, "three files stay three rows")
H.eq(small[1].path, "src/lib/db.js", "named individually")
H.eq(small[1].count, 1, "one apiece")

-- FILES NO FEATURE COULD EVER CLAIM are not counted, and the exclusion is
-- categorical rather than configured: an icon has no behavior to describe
-- and a lockfile is a record of a resolver's arithmetic. `sources` answers
-- a different question — what THIS product is made of — and a reader may
-- reasonably draw that line anywhere.
--
-- Measured on a real project: eight of seventy-two files. The cost was not
-- the eight; it was that a drafting pass kept being handed them, could not
-- describe them, and correctly concluded it had stopped making progress.
local div = require("scry.divergence")
for _, junk in ipairs({
  "public/og.png",
  "brand/avatar.svg",
  "assets/fonts/inter.woff2",
  "media/demo.mp4",
  "package-lock.json",
  "app/package-lock.json",
  "yarn.lock",
  "Cargo.lock",
  "go.sum",
}) do
  H.eq(div.describable(junk), false, junk .. " is not something a feature claims")
end

-- SOURCE IS LEFT IN, even where a reader might have excluded it. Generated
-- code is still code, content is still content, and build config is a real
-- decision someone made — scry has no business ruling on those first.
for _, real in ipairs({
  "src/lib/db.js",
  "checklists/day-hike.md",
  "README.md",
  "package.json",
  "astro.config.mjs",
  "render.yaml",
  "src/pages/index.astro",
  "scripts/setup-env.mjs",
}) do
  H.eq(div.describable(real), true, real .. " is a reader's call, not scry's")
end

H.done("divergence_spec PASS")
