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
-- the product. Divergence is the only thing on the page that says so.
--
-- The feature has to be genuinely READ as well as backed, or this measures
-- the wrong thing: an unengaged feature reads `unread` rather than `done`
-- (see feature.lua), and the sharpest version of the divergence point is a
-- feature you have been through, that really is finished, with a third of the
-- product still described by nothing.
local all_done = { at = os.time(), verdicts = {} }
for _, c in ipairs(m.claims) do
  all_done.verdicts[map.claim_id(c)] = { status = "backed", fidelity = "ts-def", label = "✓ defined" }
  require("scry.provenance").record(work, c, "authored")
end
local d = debt.count(m, all_done, work)
H.eq(d.features, 1, "one feature")
H.eq(d.done, 1, "and it is done")
H.eq(d.unread, 0, "and read, so `done` is the honest word for it")
H.eq(d.todo, 0, "nothing outstanding, by the feature axis alone")
H.eq(d.unclaimed, 4, "yet four files are described by nothing")
local header = debt.header(d, all_done.at)
H.ok(
  header:find("4 unclaimed files", 1, true) ~= nil,
  "so the header says it on the line the reader scans: " .. vim.split(header, "\n")[1]
)

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

H.done("divergence_spec PASS")
