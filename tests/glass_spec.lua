-- The glass: compose interleaves holdout nevers into their features; :write
-- splits blocks back to the right files with a notification; verdicts render
-- as extmarks; ratify stamps the cursor line.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local glass = require("scry.glass")

-- 1) compose: nevers land inside their feature, before the next header.
local composed = glass.compose({
  "feature auth",
  
  "  contains",
  "    lua/auth.lua:create_session",
  "",
  "feature billing",
}, {
  "feature auth",
  "  never",
  "    logging\\.debug",
})
local text = table.concat(composed, "\n")
local auth_pos = text:find("feature auth", 1, true)
local never_pos = text:find("  never", 1, true)
local billing_pos = text:find("feature billing", 1, true)
H.ok(never_pos and auth_pos < never_pos and never_pos < billing_pos, "never block interleaved inside its feature")

-- 2) split: the inverse routes blocks to the right files.
local map_lines, holdout_lines, count = glass.split(composed)
H.eq(count, 1, "one never claim routed")
H.ok(table.concat(map_lines, "\n"):find("never", 1, true) == nil, "map side has no never block")
H.ok(table.concat(holdout_lines, "\n"):find("logging\\.debug", 1, true) ~= nil, "holdout side has the pattern")
H.ok(table.concat(holdout_lines, "\n"):find("feature auth", 1, true) ~= nil, "holdout keeps the feature header")
-- compose(split(x)) is stable
local recomposed = glass.compose(map_lines, holdout_lines)
H.eq(table.concat(recomposed, "\n"), text, "compose∘split is identity on composed input")

-- 2b) A blank line inside a never block is layout, not a terminator. Treating
-- it as one split the block and routed the tail into the REPO map file — a
-- live prohibition committed where a repo-reading generator sees it, and
-- demoted to prose so it stopped being checked. Both halves must survive.
local paragraphed = {
  "feature sessions",
  "  never",
  "    print\\(",
  "",
  "    io\\.write",
  "",
  "feature billing",
}
local pm, ph, pn = glass.split(paragraphed)
H.eq(pn, 2, "both patterns counted across the paragraph break")
local pm_text, ph_text = table.concat(pm, "\n"), table.concat(ph, "\n")
H.ok(pm_text:find("print", 1, true) == nil, "no prohibition leaked into the repo map")
H.ok(pm_text:find("io\\.write", 1, true) == nil, "not even the one after the blank line")
H.ok(ph_text:find("print\\(", 1, true) ~= nil, "first pattern held out")
H.ok(ph_text:find("io\\.write", 1, true) ~= nil, "second pattern held out too")
-- ...and the trailing blank is map layout, not holdout content
H.eq(pm[#pm], "feature billing", "the feature header still routes to the map")
H.ok(ph[#ph]:find("io\\.write", 1, true) ~= nil, "the holdout ends at its last pattern")
-- the parser agrees: both are claims, not prose
local reparsed = require("scry.map").parse(ph)
H.eq(#reparsed.claims, 2, "the holdout reparses as two never-claims, not one plus prose")
-- and they survive the trip back into the glass
local back = glass.compose(pm, ph)
H.ok(table.concat(back, "\n"):find("io\\.write", 1, true) ~= nil, "the interleaved block is whole again")

-- 3) end-to-end against the fixture: open, check with the real resolver,
-- assert rendered verdicts; write-split to temp locations.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
for _, f in ipairs({ "auth.lua", "store.lua", "logging.lua" }) do
  vim.fn.writefile(vim.fn.readfile(H.fixture .. "/lua/" .. f), work .. "/lua/" .. f)
end
vim.fn.mkdir(work .. "/.scry", "p")
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/map.scry"), work .. "/.scry/map.scry")

require("scry").setup({ holdout_path = work .. "/holdout-test.scry" })
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/holdout.scry"), work .. "/holdout-test.scry")

require("scry.glass").open(work)
local buf = glass._state.buf
H.ok(buf ~= nil, "glass buffer created")
H.eq(vim.bo[buf].buftype, "acwrite", "glass is acwrite")
H.ok(H.wait(function()
  return glass._state.report ~= nil
end, 8000), "check settled")

local ns = vim.api.nvim_get_namespaces()["scry.glass"]
local virt = H.virt_by_row(buf, ns)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local function row_of(needle)
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      return i - 1
    end
  end
end
H.ok(virt[row_of("create_session")]:find("✓ defined", 1, true) ~= nil, "backed verdict rendered")
-- The untouched marker is the glyph alone. It used to read "∅ untouched",
-- which is twelve characters repeated down every line of a freshly drafted
-- map — the state EVERY claim starts in. As a column it is a marker you
-- scan past; as a word it was the loudest thing on a page about something
-- else. The manual carries the meaning (|scry-ownership|).
H.ok(virt[row_of("create_session")]:find("∅", 1, true) ~= nil, "untouched marker rendered")
H.eq(virt[row_of("create_session")]:find("untouched", 1, true), nil, "as the glyph, not the word")

-- Verdicts line up in a column rather than trailing whatever the line says.
-- Two claims of very different lengths must start their verdict at the same
-- screen cell, or the state column is not a column.
local function verdict_col(needle)
  local row = row_of(needle)
  local line_w = vim.fn.strdisplaywidth(lines[row + 1])
  local lead = virt[row]:match("^ *") or ""
  return line_w + #lead
end
H.eq(
  verdict_col("create_session"),
  verdict_col("::put"),
  "a 32-column claim and an 18-column one share a verdict column"
)
H.ok(virt[row_of("refresh_token")]:find("✗ absent", 1, true) ~= nil, "absent verdict rendered")
H.ok(virt[row_of("logging\\.debug")]:find("VIOLATED", 1, true) ~= nil, "violation rendered")
H.ok(virt[row_of("logging\\.debug")]:find("lua/auth.lua:9", 1, true) ~= nil, "evidence line rendered")
-- The header is NOT an extmark. It was virt_lines above line 1 and Neovim
-- never draws those — there is no room above a buffer's first line — so the
-- counts were invisible on exactly the map a new user opens first, while
-- this spec passed because the extmark existed. Existing is not drawing.
local above = 0
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  if m[4].virt_lines and m[4].virt_lines_above then
    above = above + 1
  end
end
H.eq(above, 0, "no virtual header above line 1, where Neovim could not draw it")
H.ok(glass.winbar():find("claims", 1, true) ~= nil, "the counts are in the winbar: " .. glass.winbar())
H.ok(glass.winbar():find("files on disk", 1, true) ~= nil, "and so does the disk caveat")

-- 4) ownership is inferred from the work: record an authored event for the
-- cursor claim and the marker clears on the next render — no command, no stamp
local prov = require("scry.provenance")
local target_claim
for _, c in ipairs(glass._state.map.claims) do
  if c.target == "lua/auth.lua:create_session" then
    target_claim = c
  end
end
prov.record(work, target_claim, "authored")
require("scry.glass").render()
local virt2 = H.virt_by_row(buf, ns)
H.ok(virt2[row_of("create_session")]:find("∅ untouched", 1, true) == nil, "a claim with a trail loses the marker")

-- 5) write: split-save both files + notification
local notified
local rn = vim.notify
vim.notify = function(msg)
  notified = msg
end
vim.api.nvim_buf_call(buf, function()
  vim.cmd("silent write")
end)
vim.notify = rn
H.ok(notified and notified:find("never%-claim") ~= nil, "write notifies the holdout routing")
local saved_map = table.concat(H.read_lines(work .. "/.scry/map.scry"), "\n")
local saved_hold = table.concat(H.read_lines(work .. "/holdout-test.scry"), "\n")
H.ok(saved_map:find("create_session", 1, true) ~= nil, "map file saved")
H.ok(saved_map:find("never", 1, true) == nil, "no never block leaked into the repo map")
H.ok(saved_hold:find("logging\\.debug", 1, true) ~= nil, "holdout file holds the patterns")

-- 6) The glass is one buffer, but :Scry can be run from any project. state.root
-- is what write() saves to, so it must never point somewhere the buffer's
-- content did not come from: re-pointing it while the buffer still held
-- another project's beliefs saved those beliefs over this project's map.
local other = vim.fn.tempname()
vim.fn.mkdir(other .. "/.scry", "p")
vim.fn.mkdir(other .. "/lua", "p")
vim.fn.writefile({ "local M = {}", "function M.only_here() end", "return M" }, other .. "/lua/other.lua")
vim.fn.writefile({ "feature other", "", "  contains", "    lua/other.lua:only_here" }, other .. "/.scry/map.scry")

require("scry.glass").open(other)
H.ok(H.wait(function()
  return glass._state.root == other and glass._state.report ~= nil
end, 8000), "opening a second project re-composes the glass")
local shown = table.concat(vim.api.nvim_buf_get_lines(glass._state.buf, 0, -1, false), "\n")
H.ok(shown:find("only_here", 1, true) ~= nil, "the buffer shows the second project")
H.ok(shown:find("create_session", 1, true) == nil, "and not the first project's beliefs")

vim.api.nvim_buf_call(glass._state.buf, function()
  vim.cmd("silent write")
end)
local first_map = table.concat(H.read_lines(work .. "/.scry/map.scry"), "\n")
H.ok(first_map:find("create_session", 1, true) ~= nil, "the FIRST project's map is untouched")
H.ok(first_map:find("only_here", 1, true) == nil, "no cross-project overwrite")

-- ...and unsaved work is never silently discarded to make room for another root
vim.api.nvim_buf_set_lines(glass._state.buf, 0, 0, false, { "feature scratch" })
local warned_open
local rn2 = vim.notify
vim.notify = function(msg, level)
  if level == vim.log.levels.WARN then
    warned_open = msg
  end
end
require("scry.glass").open(work)
vim.notify = rn2
H.eq(glass._state.root, other, "a modified glass refuses to re-point at another root")
H.ok(warned_open and warned_open:find("unsaved", 1, true) ~= nil, "and says why: " .. tostring(warned_open))

-- The winbar answers for whatever window asks, so it empties itself when a
-- window stops showing the glass instead of stranding a stale header there.
vim.cmd("enew")
H.eq(glass.winbar(), "", "no winbar outside the glass")
vim.api.nvim_set_current_buf(buf)
H.ok(glass.winbar():find("features", 1, true) ~= nil, "and the counts come back in it")

H.done("glass_spec PASS")
