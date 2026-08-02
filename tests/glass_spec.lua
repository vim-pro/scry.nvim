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

-- ONE BLANK LINE AT THE TOP, and a REAL one. Every other gap in this buffer
-- is virtual, but there is no room above a buffer's first line for Neovim to
-- draw in, so air under the header has to be a line. It costs a leading blank
-- in the map file, which is the honest price.
H.eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "", "the glass opens with a blank line")

-- A WRAPPED LINE KEEPS ITS INDENT. Indentation is this buffer's grammar, so a
-- continuation starting in column one reads as a new line at the outermost
-- level — a feature's description looked like it had turned into something
-- else halfway through a sentence.
H.eq(vim.wo.breakindent, true, "wrapped lines keep the indent their line started at")
H.eq(vim.wo.linebreak, true, "and break at words, since prose broken mid-word is prose you re-read")

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

-- RENDER WHAT VARIES, ONE ALTITUDE DOWN. The folded map already drops a
-- column that reads the same on every row; an EXPANDED feature did not, and
-- that is where the repetition was worst — four members deep, every one of
-- them saying `✓ present (file) · ∅`, the identical twenty-two characters
-- under a header that had just said the feature was whole and unread.
--
-- So a marker that is true of every member of a feature is not printed on
-- any of them. Nothing is lost: the feature's own line is what carries it.
-- Here no claim in the fixture has been touched, so the untouched marker is
-- exactly that kind of marker.
H.eq(virt[row_of("create_session")]:find("∅", 1, true), nil, "a marker true of every member is on none of them")

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

-- WHERE A MEMBER LANDS, when the row does not already say. A kind names a
-- thing and its probe knows the file — `route [slug]` IS
-- src/pages/[slug].astro — and without that the reader is being asked to
-- agree that a capability is made of four files while looking at two of them.
local probed = require("scry.map").parse({
  "feature f",
  "  route [slug]",
  "  def lua/auth.lua:create_session",
  "  module lua/store.lua",
}, require("scry.kinds").all({ kinds = { route = { path = "src/pages/{name}.astro" } } }))
local shown = {}
for _, c in ipairs(probed.claims) do
  local p = require("scry.map").claim_path(c, require("scry.kinds").all({
    kinds = { route = { path = "src/pages/{name}.astro" } },
  }))
  shown[c.target] = p and c.target:find(p, 1, true) ~= 1
end
H.eq(shown["[slug]"], true, "a kind-named member says which file it is")
-- Not merely "different from the target". `def lua/auth.lua:create_session`
-- resolves to `lua/auth.lua`, which the row already opens with — printing it
-- beside itself is the texture this whole rule exists to remove.
H.eq(shown["lua/auth.lua:create_session"], false, "a target that already opens with its path does not repeat it")
H.eq(shown["lua/store.lua"], false, "nor does one that IS its path")
H.ok(virt[row_of("logging\\.debug")]:find("VIOLATED", 1, true) ~= nil, "violation rendered")
H.ok(virt[row_of("logging\\.debug")]:find("lua/auth.lua:9", 1, true) ~= nil, "evidence line rendered")
-- NOTHING VIRTUAL ABOVE LINE 1. Neovim has no room to draw there, so a mark
-- placed above the first line exists without ever appearing — which is
-- precisely how this buffer's header was invisible for a while, with a spec
-- passing because the extmark existed. Existing is not drawing.
--
-- The breathing-room separators between features are virt_lines_above too
-- (below), so this is about row 0 rather than about the whole buffer.
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
  if m[2] == 0 then
    H.eq(m[4].virt_lines_above, nil, "no virtual line above line 1, where Neovim could not draw it")
  end
end
-- The glass's own winbar fits itself to the window, so what survives at a
-- spec's window width is the features half. That it is populated at all is
-- the property under test; debt.winbar owns which half.
H.ok(glass.winbar():find("features", 1, true) ~= nil, "the counts are in the winbar: " .. glass.winbar())

-- A FEATURE'S NAME IS NOT A HEADING. There are as many names as features and
-- a closed map is nothing but names, so coloring them Title painted the
-- whole page the scheme's loudest color — nine lines of yellow, saying only
-- that each line is a line. Bold and otherwise untouched: structure without
-- a hue, so the only colors left on a folded map are ones that mean
-- something.
local fname = vim.api.nvim_get_hl(0, { name = "ScryFeatureName", link = false })
H.eq(fname.link, nil, "the name borrows no color group")
H.eq(fname.fg, nil, "and no color of its own")
H.eq(fname.bold, true, "it is bold, which is structure rather than hue")
-- The caveat travels with the counts, at whatever width the line was fitted
-- to; debt.winbar's own spec pins what a narrow window drops.
H.ok(
  require("scry.debt").winbar(glass._state.debt, nil):find("files on disk", 1, true) ~= nil,
  "and so does the disk caveat"
)

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
H.eq(virt2[row_of("create_session")]:find("∅", 1, true), nil, "a claim with a trail carries no marker")
-- ...and now that ONE member of that feature has been read, the marker
-- discriminates, so it comes back on the ones that have not. This is the
-- same rule in the other direction: the column earns its place the moment
-- the rows stop agreeing.
H.ok(virt2[row_of("validate_token")]:find("∅", 1, true) ~= nil, "and its untouched neighbor gets one")
-- The marker is the glyph alone. It used to read "∅ untouched", twelve
-- characters repeated down every line of a freshly drafted map — the state
-- EVERY claim starts in. As a column it is a marker you scan past; as a word
-- it was the loudest thing on a page about something else. The manual
-- carries the meaning (|scry-ownership|).
H.eq(virt2[row_of("validate_token")]:find("untouched", 1, true), nil, "as the glyph, not the word")

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

-- AN EMPTY MAP OPENS EMPTY.
--
-- There was a block of instructions here for a project with no map — what a
-- feature is, how the indentation works, which key to press. It read well and
-- it would not leave. It is PROSE, so it parsed fine and nothing ever
-- objected to it: it sat above every feature that arrived after it, came back
-- in the request behind every draft, and went into `.scry/map.scry` on the
-- first `:w` — a versioned file of someone's beliefs about their product,
-- with a tutorial at the top.
--
-- Instructions that live in the document they are teaching you to write have
-- no way out of it. The header says what to do (`+ to draft`) without being
-- part of the map, and `:Scry {intent}` (|scry-aim|) is a way in that needs
-- no reading at all.
local blank = vim.fn.tempname()
vim.fn.mkdir(blank, "p")
-- The section above deliberately left the glass modified, and a modified
-- glass refuses to re-point at another root (that is its own assertion).
vim.bo[glass._state.buf].modified = false
-- ...and a fresh holdout, since this suite pointed the configured one at a
-- file with prohibitions in it, and those compose into every glass.
require("scry").setup({ holdout_path = blank .. "/holdout.scry" })
require("scry.glass").open(blank)
local opened = vim.api.nvim_buf_get_lines(glass._state.buf, 0, -1, false)
H.eq(table.concat(opened, ""), "", "a project with no map opens to nothing at all")
H.eq(#require("scry.map").parse(opened).features, 0, "and there is nothing in it to check")
H.eq(glass.starter, nil, "the template is gone, not merely unused")

-- THE OPENING BLANK IS ADDED ONCE, NOT EVERY TIME. It is a real line, so it
-- is saved with the map — and a map reopened would otherwise grow another
-- blank on every visit, which is a document slowly walking down the screen.
local spaced = vim.fn.tempname()
vim.fn.mkdir(spaced .. "/.scry", "p")
vim.fn.writefile({ "", "feature already spaced", "  module a.lua" }, spaced .. "/.scry/map.scry")
require("scry").setup({ holdout_path = spaced .. "/holdout.scry" })
require("scry.glass").open(spaced)
local reopened = vim.api.nvim_buf_get_lines(glass._state.buf, 0, -1, false)
H.eq(reopened[1], "", "a map that already starts blank still starts blank")
H.eq(reopened[2], "feature already spaced", "and its first feature has not been pushed down again")

-- RENDER WHAT VARIES. A column that says the same thing on every row is not
-- information, it is texture. Measured on a real drafted map: fourteen rows,
-- ONE distinct verdict state between them, and not one row whose fraction
-- differed from `N of N` — three hundred and fifty characters repeating,
-- while the header above already said `14 unread · 50 backed · 0 missing`.
local function fold_line(lnum)
  local out = ""
  for _, c in ipairs(glass.foldtext(lnum)) do
    out = out .. c[1]
  end
  return out
end

local function staged(lines, status)
  local mm = require("scry.map")
  local m = mm.parse(lines, {})
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, b)
  local report = { at = os.time(), verdicts = {} }
  for i, c in ipairs(m.claims) do
    report.verdicts[mm.claim_id(c)] = { status = status(i), label = "x" }
  end
  glass._state.buf, glass._state.map, glass._state.root, glass._state.report = b, m, ".", report
  glass.render()
  return m
end

-- Every feature reading the same: the words go.
staged({
  "feature Work through a checklist",
  "  module a.lua",
  "  module b.lua",
  "feature Tailor a checklist",
  "  module c.lua",
}, function()
  return "backed"
end)
local uniform_first = fold_line(1)
H.eq(uniform_first:find("unread"), nil, "a state every row shares is not printed on every row")
H.eq(uniform_first:find(" of "), nil, "nor is a fraction that says nothing is missing")
H.ok(uniform_first:find("Work through a checklist", 1, true) ~= nil, "the name survives")
H.ok(uniform_first:find("▍", 1, true) ~= nil, "and the size is a shape rather than a word")

-- One feature differing: the words come back, and only where they earn it.
staged({
  "feature Work through a checklist",
  "  module a.lua",
  "  module b.lua",
  "feature Tailor a checklist",
  "  module c.lua",
}, function(i)
  return i == 1 and "missing" or "backed"
end)
local varied = fold_line(1)
H.ok(varied:find(" of ", 1, true) ~= nil, "a partial feature shows how far along it is")

-- COLUMN ONE IS THE ATTENTION CHANNEL, and it says nothing when a feature is
-- fine. A scan reads the first characters of each line and little else, so
-- marking every row would mark none of them.
H.ok(varied:sub(1, 3):find("%S") ~= nil, "a feature that wants you carries a mark")
local healthy = fold_line(4)
H.eq(healthy:sub(1, 3), "   ", "and one that does not carries nothing")

-- The mark is not also spelled out on the right: it moved, it was not copied.
local _, glyphs = varied:gsub("◐", "")
H.ok(glyphs <= 1, "the glyph appears once, not once per column")

-- THE DEFAULT VIEW SHOWS WHAT A FEATURE IS, NOT JUST ITS NAME.
--
-- With one fold per feature, everything under the name was inside it, so the
-- only closed view was a stack of bare titles — and a title is the part a
-- reader can already guess. The description is the one piece of writing they
-- most need, and it was the first thing hidden.
--
-- Two levels fix it without a mode: the name and its sentence are level 1,
-- the members are level 2. `zM` still gives the dense scan, the default gives
-- titles AND sentences, `zR` gives the files. Vim already had the control.
local desc = staged({
  "feature Read a checklist as markdown or JSON",
  "  Every checklist is fetchable as its source markdown.",
  "  module a.lua",
  "  module b.lua",
  "  module c.lua",
  "",
  "feature Work through a checklist",
  "  module d.lua",
}, function()
  return "backed"
end)
H.eq(glass.foldexpr(2), "1", "the sentence saying what a feature is stays out of the members fold")
H.eq(glass.foldexpr(3), ">2", "which the members open for themselves")

-- The closed members fold is the blast radius and nothing else. The feature's
-- own line four rows up has already printed its state, so repeating the
-- fraction here would be the same defect one altitude down.
local members = ""
for _, c in ipairs(glass.foldtext(3, 5)) do
  members = members .. c[1]
end
H.ok(members:find("▍", 1, true) ~= nil, "the members row carries the size")
H.eq(members:find("%d"), nil, "and not a count the feature line already gave")

-- BREATHING ROOM IS RENDERED, NOT WRITTEN. A drafting pass emits features
-- with no blank line between them, and scry does not get to edit someone's
-- file to add whitespace — so the separator is virtual, and only where the
-- author has not already left one.
local ns2 = vim.api.nvim_get_namespaces()["scry.glass"]
local sep = {}
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(glass._state.buf, ns2, 0, -1, { details = true })) do
  if m[4].virt_lines_above then
    sep[m[2]] = true
  end
end
H.eq(#desc.features, 2, "two features staged")
H.eq(sep[0], nil, "no separator above the first feature, where Neovim cannot draw one")
H.eq(sep[6], nil, "nor above one the author already spaced")

-- AND AIR BETWEEN THE SENTENCE AND THE FILE LIST — what a feature IS and what
-- it is MADE OF, which are the two altitudes this whole buffer is built
-- around and which were running together as one block.
--
-- Attached BELOW the last line of the description, not above the first
-- member. The members are a fold, and a mark above a closed fold's first line
-- is never drawn — Neovim has nowhere to put it — so anchoring it there would
-- have made the gap vanish in exactly the default view.
local below = {}
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(glass._state.buf, ns2, 0, -1, { details = true })) do
  if m[4].virt_lines and not m[4].virt_lines_above then
    below[m[2]] = true
  end
end
H.eq(below[1], true, "the description is spaced off from the members")
H.eq(below[0], nil, "and the gap hangs off the description, not off the feature's name")

-- A feature with no description reads fine tight, so it gets nothing.
staged({ "feature one", "  module a.lua", "feature two", "  module b.lua" }, function()
  return "backed"
end)
local none = 0
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(glass._state.buf, ns2, 0, -1, { details = true })) do
  if m[4].virt_lines and not m[4].virt_lines_above then
    none = none + 1
  end
end
H.eq(none, 0, "a feature whose members follow its name directly is not spaced")

local tight = staged({
  "feature one",
  "  module a.lua",
  "feature two",
  "  module b.lua",
}, function()
  return "backed"
end)
H.eq(#tight.features, 2, "two adjacent features staged")
local tight_sep = {}
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(glass._state.buf, ns2, 0, -1, { details = true })) do
  if m[4].virt_lines_above then
    tight_sep[m[2]] = true
  end
end
H.eq(tight_sep[2], true, "a feature the drafter left flush against the last one gets one")

-- AND THE MEMBERS THEMSELVES GO QUIET WHEN THEY AGREE. Same rule, applied
-- inside an expanded feature — which is where the repetition was worst.
local mixed = staged({
  "feature agreed",
  "  module a.lua",
  "  module b.lua",
  "feature split",
  "  module c.lua",
  "  module d.lua",
}, function(i)
  return i == 4 and "missing" or "backed"
end)
H.eq(#mixed.claims, 4, "four members staged")
local mvirt = H.virt_by_row(glass._state.buf, ns2)
H.eq(mvirt[1], nil, "two members that agree are annotated on neither")
H.eq(mvirt[2], nil, "not the second one either")
H.ok(mvirt[4] and mvirt[4]:find("x", 1, true) ~= nil, "but a member that differs from its neighbor is")
H.ok(mvirt[5] and mvirt[5]:find("x", 1, true) ~= nil, "and so is the one it differs from")

-- ONLY A HEALTHY VERDICT IS EVER WITHHELD, because silence has to mean one
-- thing and the thing it means is "fine". Suppressing whatever the members
-- happened to AGREE on meant a feature whose every file was missing rendered
-- exactly as blank as one where every file was there — and the reader had no
-- way to tell which of the two they were looking at.
staged({
  "feature nothing here exists",
  "  module a.lua",
  "  module b.lua",
}, function()
  return "missing"
end)
local gone = H.virt_by_row(glass._state.buf, ns2)
H.ok(gone[1] and gone[1]:find("x", 1, true) ~= nil, "members that agree they are MISSING all say so")
H.ok(gone[2] and gone[2]:find("x", 1, true) ~= nil, "every one of them, not none of them")

-- A LONE MEMBER IS NEVER UNIFORM WITH ANYTHING, so it always says what it is.
-- Suppressing a column of one is not removing repetition, it is removing the
-- only copy.
local alone = staged({ "feature solo", "  module a.lua" }, function()
  return "backed"
end)
H.eq(#alone.claims, 1, "one member staged")
local avirt = H.virt_by_row(glass._state.buf, ns2)
H.ok(avirt[1] and avirt[1]:find("x", 1, true) ~= nil, "a feature's only member keeps its verdict")

-- ]d AND [d — MOTIONS INSTEAD OF GROUPING.
--
-- The obvious way to surface what needs attention is to group by state with
-- headings, and it is wrong here: the buffer IS the file, so grouping means
-- reordering, and reordering means rewriting someone's document to suit a
-- view of it. Vim's answer to "take me to the one that matters" was never
-- sorting; it was motions. `]d~` is then "fix the next broken thing", and
-- `.` repeats it.
local m = staged({
  "feature healthy one",
  "  module a.lua",
  "feature the broken one",
  "  module b.lua",
  "feature another healthy one",
  "  module c.lua",
  "feature the other broken one",
  "  module d.lua",
}, function(i)
  return (i == 2 or i == 4) and "missing" or "backed"
end)
H.eq(#m.features, 4, "four features staged")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
H.eq(glass.wants_attention(1), true, "]d moves")
H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "to the next feature that wants something, skipping the healthy one")
H.eq(glass.wants_attention(1), true, "and again")
H.eq(vim.api.nvim_win_get_cursor(0)[1], 7, "to the one after that")

-- IT DOES NOT WRAP. A motion that silently starts over hides the fact that
-- you have seen everything, and "no more" is the answer you most want at the
-- end of a pass.
H.eq(glass.wants_attention(1), false, "and stops at the end rather than starting over")
H.eq(vim.api.nvim_win_get_cursor(0)[1], 7, "leaving the cursor where it was")

H.eq(glass.wants_attention(-1), true, "[d goes back")
H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "to the previous one")
H.eq(glass.wants_attention(-1), false, "and stops at the top too")

-- A map with nothing wrong has nowhere to go, and says so rather than
-- moving somewhere arbitrary.
staged({ "feature all fine", "  module a.lua" }, function()
  return "backed"
end)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
H.eq(glass.wants_attention(1), false, "a healthy map has nothing to jump to")

H.done("glass_spec PASS")
