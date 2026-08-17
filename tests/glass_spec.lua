-- The glass: the map file as one editable buffer; verdicts render as
-- extmarks, computed and never stored; :write writes the map.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local glass = require("scry.glass")

-- 2b) A blank line inside a never block is layout, not a terminator.
-- Treating it as one silently demotes every pattern after it to prose — a
-- prohibition that stops being checked. Both halves must survive the parse.
local paragraphed = {
  "feature sessions",
  "  never",
  "    print\\(",
  "",
  "    io\\.write",
  "",
  "feature billing",
}
local reparsed = require("scry.map").parse(paragraphed)
H.eq(#reparsed.claims, 2, "both patterns parse as never-claims across the paragraph break")

-- 3) end-to-end against the fixture: open, check with the real resolver,
-- assert rendered verdicts; write to temp locations.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
for _, f in ipairs({ "auth.lua", "store.lua", "logging.lua" }) do
  vim.fn.writefile(vim.fn.readfile(H.fixture .. "/lua/" .. f), work .. "/lua/" .. f)
end
vim.fn.mkdir(work .. "/.scry", "p")
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/map.scry"), work .. "/.scry/map.scry")

require("scry").setup({})

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
  verdict_col("store.lua:put"),
  "a long claim and a short one share a verdict column"
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
  require("scry.header").winbar(glass._state.tally, nil):find("files on disk", 1, true) ~= nil,
  "and so does the disk caveat"
)

-- 4) THERE IS NO ENGAGEMENT AXIS. The ∅ marker, the per-machine trail behind
-- it, and the `unread` feature state were the last of the ratification
-- design: a whole subsystem that said nothing about the code. A reader
-- looking at `– unread 4 of 4` beside four members each already showing their
-- own verdict learned nothing they could act on.
H.eq(package.loaded["scry.provenance"], nil, "the trail module is gone")
H.eq(pcall(require, "scry.provenance"), false, "and not merely unloaded")
for _, row in pairs(H.virt_by_row(buf, ns)) do
  H.eq(row:find("∅", 1, true), nil, "no ownership marker survives anywhere: " .. row)
end

-- 5) write: the buffer is the map file
local notified
local rn = vim.notify
vim.notify = function(msg)
  notified = msg
end
vim.api.nvim_buf_call(buf, function()
  vim.cmd("silent write")
end)
vim.notify = rn
H.ok(notified and notified:find("map →") ~= nil, "write says where the map went")
local saved_map = table.concat(H.read_lines(work .. "/.scry/map.scry"), "\n")
H.ok(saved_map:find("create_session", 1, true) ~= nil, "map file saved")
H.ok(saved_map:find("logging\\.debug", 1, true) ~= nil, "prohibitions saved with it, versioned like everything else")

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
H.ok(glass.winbar():find("feature", 1, true) ~= nil, "and the counts come back in it")

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
require("scry.glass").open(spaced)
local reopened = vim.api.nvim_buf_get_lines(glass._state.buf, 0, -1, false)
H.eq(reopened[1], "", "a map that already starts blank still starts blank")
H.eq(reopened[2], "feature already spaced", "and its first feature has not been pushed down again")

-- RENDER WHAT VARIES. A column that says the same thing on every row is not
-- information, it is texture. Measured on a real drafted map: fourteen rows,
-- ONE distinct verdict state between them, and not one row whose fraction
-- differed from `N of N` — three hundred and fifty characters repeating,
-- while the header above already said `14 done · 50 backed · 0 missing`.
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
-- ONE CELL OF MAGNITUDE, scaled to the map. Ten ▍ blocks per row made a
-- fifteen-feature page's dominant ink a brick wall that read as a
-- rendering fault. The biggest feature is █; the rest sit under it.
H.ok(uniform_first:find("█", 1, true) ~= nil, "the biggest feature is full height")
local uniform_second = fold_line(4)
H.ok(uniform_second:find("▄", 1, true) ~= nil, "half the members is half the height")
H.eq(uniform_first:find("▍", 1, true), nil, "the brick wall is gone")
H.eq(uniform_first:find("…", 1, true), nil, "and nothing trails off")

-- A BLOCK'S TRAILING BLANKS STAY OUTSIDE THE FOLD. Folded in, every closed
-- feature sat flush against the next — a blob — and an opened one had no
-- boundary. A blank inside a body still folds.
local fb = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(fb, 0, -1, false, {
  "feature one",
  "  prose about it",
  "",
  "  module a.lua",
  "",
  "getting on the water",
  "",
  "feature two",
  "  module b.lua",
  "",
  "feature three",
  "  module c.lua",
})
vim.api.nvim_win_set_buf(0, fb)
glass._state.buf = fb
H.eq(glass.foldexpr(1), ">1", "a feature opens a fold")
H.eq(glass.foldexpr(3), "1", "a blank inside the body folds with it")
H.eq(glass.foldexpr(5), "0", "the blank above a heading is the air between groups")
-- ONE LEVEL OF GROUPING. A flush-left prose line between features is a
-- heading: still prose to the parser, but it stays outside every fold —
-- folded into the block above, it would vanish from the closed view it
-- exists to organize.
H.eq(glass.foldexpr(6), "0", "a heading stays outside every fold")
H.eq(glass.foldexpr(7), "0", "so does the blank under it")
H.eq(glass.foldexpr(9), "1", "and the next body folds as ever")
-- WHERE THE AIR IS: around groups, not between features. The blank between
-- two features stays in the FILE for the open view, but the closed scan
-- folds it away, so a group reads as a tight run of sentences.
H.eq(glass.foldexpr(10), "1", "a blank between two features folds away in the scan")
H.eq(glass.foldexpr(11), ">1", "and the next feature still opens its own fold")

-- ...and a heading is a heading WHEREVER it sits. The feature-block syntax
-- region ran to the next `feature` line, so a heading between features was
-- inside the previous block — where only the contains list may match — and
-- the same line rendered as structure or as dimmed prose depending on
-- nothing but its position.
vim.cmd("syntax enable")
local hroot = vim.fn.tempname()
vim.fn.mkdir(hroot .. "/.scry", "p")
vim.fn.writefile({
  "Top heading",
  "",
  "feature one",
  "  Prose about it.",
  "  module a.lua",
  "",
  "Mid heading",
  "",
  "feature two",
  "  module b.lua",
}, hroot .. "/.scry/map.scry")
vim.bo[glass._state.buf].modified = false
require("scry.glass").open(hroot)
H.ok(H.wait(function()
  return glass._state.root == hroot and glass._state.report ~= nil
end, 8000), "the heading map opened")
-- The suite runs --noplugin, so the FileType-driven syntax load never
-- fired for this buffer; source it directly.
vim.api.nvim_buf_call(glass._state.buf, function()
  vim.cmd("setlocal syntax=scry")
end)
local function syn_of(needle)
  return vim.api.nvim_buf_call(glass._state.buf, function()
    for l = 1, vim.api.nvim_buf_line_count(0) do
      if vim.fn.getline(l):find(needle, 1, true) then
        return vim.fn.synIDattr(vim.fn.synID(l, 1, true), "name")
      end
    end
    return "(line not found)"
  end)
end
H.eq(syn_of("Top heading"), "ScryHeading", "a heading above the first feature is a heading")
H.eq(syn_of("Mid heading"), "ScryHeading", "and so is one between features — position changes nothing")
-- The harness runs --noplugin, where the description's group resolves
-- differently than in a live session; the boundary this test owns is that
-- indented prose is never promoted to a heading.
H.ok(syn_of("Prose about it") ~= "ScryHeading", "indented prose is never a heading")

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

-- MEMBERS ARE SIMPLY VISIBLE. The fold that tucked them into a bar under
-- the description is gone (see locate_spec for the fold shape); what remains
-- foldable is the feature itself, whose closed row is the scan.
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

-- EVERY OPEN ROW SAYS WHAT IT IS.
--
-- A member's verdict used to be withheld when every member of a feature
-- agreed — the same "render what varies" rule the folded scan follows. That
-- rule was measured on the SCAN: fourteen features, one state between them,
-- three hundred characters of pure texture. Carrying it down here was a
-- mistake.
--
-- At a member row the reader is not scanning for anomalies, they are
-- VERIFYING AN ADDRESS: is that the right file, is it really there. Each row
-- is a separate assertion, and a silent one makes you recall a rendering rule
-- before you can interpret it. Having just asked a model which files a
-- capability is made of, "nothing is written here, which means they agreed,
-- which means fine" is not a thing to make someone reconstruct.
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
for row = 1, 5 do
  if row ~= 3 then
    H.ok(mvirt[row] and mvirt[row]:find("x", 1, true) ~= nil, "row " .. row .. " carries its own verdict")
  end
end

-- AND SO DOES AN OPEN FEATURE LINE. Its state was withheld when every feature
-- in the map read the same — which, in a map with ONE feature, is always. The
-- only row on the page said nothing at all.
local lone = staged({ "feature the only one here", "  module a.lua" }, function()
  return "backed"
end)
H.eq(#lone.features, 1, "one feature staged")
local lvirt = H.virt_by_row(glass._state.buf, ns2)
H.ok(lvirt[0] and lvirt[0]:find("%S") ~= nil, "a map of one feature still says how that feature stands")

-- The folded SCAN still drops what repeats, because there the density
-- argument is real and the header carries the fact. Two views, two jobs.
H.eq(fold_line(1):find("unread"), nil, "the scan view is unchanged")

-- THE PLAN'S WORDS RENDER ON THE ROW. `~ change` and `+ create` were
-- states a reader had to assemble from a note plus the verdict column; they
-- are a word now, in the diff colors every scheme already has.
require("scry.plan").clear()
local planned_map = staged({
  "feature planned one",
  "  module exists.lua",
  "    add the print styles",
  "  module absent.lua",
  "    the new sheet",
  "  module quiet.lua",
}, function()
  return "backed"
end)
H.eq(#planned_map.features, 1, "one feature staged")
-- exists.lua is real for this test; absent.lua is not
vim.fn.writefile({ "x" }, "exists.lua")
require("scry.plan").pending = { feature = "planned one" }
glass.render()
local pvirt = H.virt_by_row(glass._state.buf, ns2)
H.ok(pvirt[1] and pvirt[1]:find("~ change", 1, true) ~= nil, "a noted member with a file reads `~ change`")
H.ok(pvirt[3] and pvirt[3]:find("+ create", 1, true) ~= nil, "a noted member without one reads `+ create`")
H.eq(pvirt[5] and pvirt[5]:find("change", 1, true), nil, "an unnoted member carries no plan word")
vim.fn.delete("exists.lua")
require("scry.plan").clear()

-- <Tab> ON A CHANGED MEMBER PEEKS THE DIFF, without leaving the map. The
-- review tab is the full walk; this is the look you take before deciding to
-- walk. Capped, because a forty-hunk diff inline in the map stops being a
-- glance.
local peek_root = vim.fn.tempname()
vim.fn.mkdir(peek_root, "p")
vim.fn.writefile({ "line one", "line two", "line three" }, peek_root .. "/style.css")
local pbuf = vim.fn.bufadd(peek_root .. "/style.css")
vim.fn.bufload(pbuf)
vim.api.nvim_buf_set_lines(pbuf, 1, 2, false, { "CHANGED two" })

staged({ "feature peekable", "  module style.css" }, function()
  return "backed"
end)
glass._state.root = peek_root
vim.api.nvim_win_set_cursor(0, { 2, 0 })
H.eq(glass.toggle_diff(), true, "<Tab> on a member with an unsaved change shows the diff")
local dns = vim.api.nvim_get_namespaces()["scry.diff"]
local dmarks = vim.api.nvim_buf_get_extmarks(glass._state.buf, dns, 0, -1, { details = true })
H.eq(#dmarks, 1, "as one block under the row")
local dtext = {}
for _, vl in ipairs(dmarks[1][4].virt_lines) do
  dtext[#dtext + 1] = vl[1][1]
end
local joined_diff = table.concat(dtext, "\n")
H.ok(joined_diff:find("-line two", 1, true) ~= nil, "what was there, marked removed")
H.ok(joined_diff:find("+CHANGED two", 1, true) ~= nil, "what replaced it, marked added")

H.eq(glass.toggle_diff(), true, "<Tab> again puts it away")
H.eq(#vim.api.nvim_buf_get_extmarks(glass._state.buf, dns, 0, -1, {}), 0, "and nothing is left behind")

-- CAPPED. A big diff shows its head and says how much more there is — the
-- glance must not become the review.
local big = {}
for i = 1, 80 do
  big[i] = "new line " .. i
end
vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, big)
H.eq(glass.toggle_diff(), true, "a big diff still peeks")
local bmarks = vim.api.nvim_buf_get_extmarks(glass._state.buf, dns, 0, -1, { details = true })
local n_rows = #bmarks[1][4].virt_lines
H.ok(n_rows <= 21, "but capped: " .. n_rows .. " rows shown")
local tail = bmarks[1][4].virt_lines[n_rows][1][1]
H.ok(tail:find("more line", 1, true) ~= nil, "with the remainder counted rather than hidden")
glass.toggle_diff()

-- A saved file has no diff to peek — the change IS the disk — so <Tab>
-- falls through to the fold, which is what the key means everywhere else.
vim.bo[pbuf].modified = false
H.eq(glass.toggle_diff(), false, "no unsaved change, no peek: the key falls through to the fold")

-- WHAT TO DO NEXT, ON THE LINE YOU ARE ALREADY READING.
--
-- The header said `+ to draft` and nothing else, forever. It went wrong two
-- ways: it vanished entirely once a project was fully described — the state
-- with the fewest reasons to guess — and it named DRAFTING even when the
-- cursor sat on a capability you had just written and plainly wanted to
-- build, while the operator that would build it was not named anywhere on
-- the screen.
staged({
  "feature a described one",
  "  module a.lua",
  "feature a bare one",
}, function()
  return "backed"
end)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
H.eq(glass.next_action(), "~ to change it", "on a feature with members, the operator is named")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
H.ok(glass.next_action():find("+", 1, true) ~= nil, "on a feature made of nothing, the way to fill it is")
-- IT IS NEVER SILENT. "I do not know what to do here" is the state this
-- exists to remove, and a fully described project sat in it permanently.
glass._state.tally = { unclaimed = 0 }
vim.api.nvim_win_set_cursor(0, { 1, 0 })
H.ok(glass.next_action() ~= nil, "and there is always something to say")

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
