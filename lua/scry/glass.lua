-- The glass: one editable buffer composed from two files — the in-repo map
-- and the out-of-repo holdout — with computed verdicts rendered as extmarks
-- and NEVER stored. Writing the glass parses the buffer and routes blocks
-- back: never-sections to the holdout, everything else to the map, with a
-- notification so storage routing is never silent.
local M = {}

local ns = vim.api.nvim_create_namespace("scry.glass")
-- Peeked inline diffs (see M.toggle_diff). Its own namespace so a render can
-- clear stale peeks without touching them being part of the verdict pass —
-- and declared HERE because render() clears it: a `local` further down the
-- file would be a nil global from render's point of view.
local diff_ns = vim.api.nvim_create_namespace("scry.diff")

-- The palette. Every group is a `default link`, so a colorscheme that
-- defines any of them wins and nothing here has to know about colors.
--
-- Two principles decide the links. Verdicts borrow the DIAGNOSTIC groups,
-- because a verdict is the same kind of thing a diagnostic is and every
-- scheme has already made those legible against its own background. The
-- buffer's own text borrows SYNTAX groups, because the map is a language
-- and reads best when it is colored like one.
--
local HL = {
  -- the page
  --
  -- The header is the frame around the counts, not a heading. As Title it
  -- was a band of the loudest color the scheme has, spent on the words
  -- "scry", "features" and "checked" — none of which is news. The counts
  -- inside it are states and carry the state colors; everything else here
  -- recedes.
  ScryHeader = "Normal",
  ScryHeaderDim = "Comment",
  ScryEvidence = "Comment",
  ScryProse = "Comment",
  -- The feature's own description is the one piece of writing a reader most
  -- needs and it was dimmed like everything else. Normal, not Comment: it
  -- is not an aside, it is the sentence the feature is.
  ScryDescription = "Normal",
  -- A member's intent is a note about one member — quieter than the
  -- feature's sentence, louder than nothing.
  ScryIntent = "Comment",
  -- The kind word leads a member line and says what sort of thing it is.
  ScryKind = "Type",

  -- the grammar
  ScryKeyword = "Statement", -- the word `feature`
  -- NOT Title. A feature's name is the sentence you read, and there are as
  -- many of them as there are features — a closed map is nothing but names,
  -- so coloring them as headings painted the entire page one color. Bold and
  -- otherwise untouched: structure without a hue, and the only colors left on
  -- a folded map are the ones that mean something.
  ScryFeatureName = false,
  ScrySection = "Type", -- contains / exercises
  -- PreProc rather than the semantically tempting Exception: Exception
  -- collapses into Statement in the stock scheme, which is exactly where
  -- the `feature` keyword already lives, so a prohibition and a feature
  -- would have rendered identically. Setting `never` apart is the whole
  -- reason it has its own group.
  ScryNever = "PreProc",
  ScryPath = "Directory",
  ScrySeparator = "Delimiter",
  ScrySymbol = "Identifier",

  -- claim verdicts
  ScryBacked = "DiagnosticOk",
  -- The plan's states borrow the DIFF groups, because that is what they are:
  -- a change and an addition the buffer knows about before it happens.
  ScryPlanChange = "Changed",
  ScryPlanCreate = "Added",
  ScryDiverged = "DiagnosticError",
  ScryUnchecked = "DiagnosticHint",

  -- Feature states: four groups, which is the whole scan — holds, partly,
  -- broken, not yet. "Structure is there" and "a spec ran" both read ✓;
  -- the row's label says which one you got.
  ScryDone = "DiagnosticOk",
  ScryBroken = "DiagnosticError",
  ScryBuilding = "DiagnosticWarn",
  ScryTodo = "DiagnosticHint",

  -- The header's what-to-do-next hint.
  ScryAction = "DiagnosticInfo",
}
for group, target in pairs(HL) do
  if target == false then
    vim.api.nvim_set_hl(0, group, { bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

-- A feature's state to the group that renders it. Module scope because BOTH
-- views need it: render() puts it at the end of an open feature line, and
-- foldtext() puts it on the closed one — and the closed map is the view a
-- reader spends most of their time in.
local FEATURE_HL = {
  done = "ScryDone",
  in_place = "ScryDone",
  broken = "ScryBroken",
  partial = "ScryBuilding",
  absent = "ScryTodo",
  unevidenced = "ScryTodo",
  unknown = "ScryTodo",
}

-- WHICH STATES WANT YOU, in the folded scan. Column one is the most valuable
-- space on the screen — a scan reads the first characters of each line and
-- little else — and it was spent on the first letter of a sentence, fourteen
-- times over. It carries state instead, and carries nothing when a feature is
-- fine, because marking every row would mark none of them.
local ATTENTION = {
  broken = "✗",
  absent = "✗",
  unevidenced = "·",
  partial = "◐",
  unknown = "?",
}

--- What the map looks like as a whole, computed once per render.
---
--- RENDER WHAT VARIES. A column that says the same thing on every row is not
--- information, it is texture. Measured on a real map: fourteen rows, one
--- distinct verdict state between them, not one row whose fraction differed
--- from `N of N` — three hundred and fifty characters repeating while the
--- header already said `14 done · 50 backed · 0 missing · 0 violated`.
---
--- So the verdict column appears when it discriminates and stays away when
--- it does not.
---@param map table
---@param report table?
---@param root string?
---@return { uniform: boolean }
local function survey(map, report, root)
  if not report then
    return { uniform = false }
  end
  local feat = require("scry.feature")
  local seen, n = {}, 0
  for _, f in ipairs(map.features or {}) do
    local v = feat.verdict(f, report, root)
    if v and not seen[v.state] then
      seen[v.state] = true
      n = n + 1
    end
  end
  return { uniform = n <= 1 }
end

-- The blast radius of a `~`, as a shape rather than a word. A magnitude read
-- as a length is faster than one read as "5 members", and this is the number
-- you want before aiming an operator at a capability.
local BAR_MAX = 10
local function bar(n)
  if n <= 0 then
    return ""
  end
  return ("▍"):rep(math.min(n, BAR_MAX)) .. (n > BAR_MAX and "…" or "")
end

--- The verdict's words, or nothing, under the same rule everywhere.
---
--- Two edits to the engine's own wording, and no wording of its own — the
--- glass may not say something stronger than the verdict said.
---
--- The whole label goes when the map does not discriminate: if every feature
--- reads the same, the header has already said so once and fourteen more
--- copies are texture. A trailing `N of N` goes when nothing is missing:
--- "3 of 3" is a longer way of writing what the absence of a fraction
--- already writes.
---@param verdict table?
---@param uniform boolean whether every feature in the map reads the same
---@return string
local function verdict_words(verdict, uniform)
  if not verdict then
    return ""
  end
  local partial = verdict.total and verdict.backed and verdict.backed < verdict.total
  if not partial and uniform then
    return ""
  end
  if partial then
    return verdict.label
  end
  return (verdict.label:gsub("%s*%(?%d+ of %d+%)?$", ""))
end

-- WHICH LINES ARE MEMBERS, as against the sentence a feature is.
--
-- The same test the parser makes, and it has to be: a fold that disagrees
-- with the grammar hides a line the grammar checks. Shape alone cannot
-- decide it — `  module src/page.tsx` and `  Search published checklists.`
-- have the same shape — so the kinds in force are handed in, exactly as
-- map.parse takes them.
local SECTIONS = { contains = true, never = true, exercises = true }

---@param line string
---@param kinds table<string, any>?
---@return boolean
function M.is_member_line(line, kinds)
  if line:match("^    %S") then
    return true -- a claim under a section, a never-pattern, a member's note
  end
  local sec = line:match("^  (%a+)%s*$")
  if sec and SECTIONS[sec] then
    return true
  end
  local kind = line:match("^  ([%w_]+)%s+%S")
  return kind ~= nil and (kinds or {})[kind] ~= nil
end

-- Session state: one glass per project root.
local state = {
  root = nil,
  buf = nil,
  map = nil, -- combined (map + holdout) parsed view of the glass buffer
  report = nil,
  debt = nil,
  -- The kinds in force. The FOLD needs them for the same reason the parser
  -- and the syntax file do: without them a member cannot be told from prose.
  kinds = nil,
}

M._state = state -- exposed for specs

function M.current_debt()
  return state.debt
end

-- ---------------------------------------------------------------------------
-- compose / split
-- ---------------------------------------------------------------------------

-- Interleave holdout never-blocks into their features: after a feature's
-- last line in the map, before the next feature header.
---@param map_lines string[]
---@param holdout_lines string[]
---@return string[]
function M.compose(map_lines, holdout_lines)
  local mapmod = require("scry.map")

  -- Collect each holdout feature's never block lines (header excluded).
  local never_blocks = {} -- name -> lines
  do
    local current, collecting = nil, false
    -- Mirror of split()'s rule: a blank inside a block is held, and only
    -- committed once another pattern proves it was interior. Without this,
    -- the blanks split() now writes to the holdout would truncate the block
    -- on the way back in, and patterns would vanish from the glass.
    local held = {}
    for _, line in ipairs(holdout_lines) do
      local name = line:match("^feature%s+(.+)$")
      if name then
        current = vim.trim(name)
        collecting = false
        held = {}
      elseif current then
        if line:match("^  never%s*$") then
          collecting = true
          held = {}
          never_blocks[current] = never_blocks[current] or {}
          table.insert(never_blocks[current], line)
        elseif collecting and line:match("^%s*$") then
          held[#held + 1] = line
        elseif collecting and line:match("^    %S") then
          vim.list_extend(never_blocks[current], held)
          held = {}
          table.insert(never_blocks[current], line)
        else
          collecting = false
          held = {}
        end
      end
    end
  end

  local out = {}
  local m = mapmod.parse(map_lines, mapmod.kinds_for(root))
  local emitted = {}
  for i, line in ipairs(map_lines) do
    -- before the NEXT feature header (or EOF), flush the current feature's nevers
    local name = line:match("^feature%s+(.+)$")
    if name then
      -- find which feature (if any) we're leaving
      for _, c in ipairs(m.features) do
        if c.lnum < i and not emitted[c.name] and never_blocks[vim.trim(c.name)] then
          vim.list_extend(out, never_blocks[c.name])
          emitted[c.name] = true
        end
      end
    end
    out[#out + 1] = line
  end
  for _, c in ipairs(m.features) do
    if not emitted[c.name] and never_blocks[c.name] then
      vim.list_extend(out, never_blocks[c.name])
      emitted[c.name] = true
    end
  end
  -- holdout features with no map feature: append whole
  for name, block in pairs(never_blocks) do
    if not emitted[name] and not mapmod.feature(m, name) then
      out[#out + 1] = "feature " .. name
      vim.list_extend(out, block)
    end
  end
  return out
end

--- Split glass lines back into map lines and holdout lines.
---@param lines string[]
---@return string[] map_lines, string[] holdout_lines, integer never_count
function M.split(lines)
  local map_lines, holdout_lines = {}, {}
  local current_feature = nil
  local emitted_holdout_header = {}
  local in_never = false
  local never_count = 0

  -- Blank lines inside a never block are undecided until we see what follows.
  -- A blank between two patterns is part of the block and must travel to the
  -- holdout with them; a blank AFTER the last pattern is map layout. Holding
  -- them here is what keeps a paragraph break from splitting a block in two
  -- and depositing the tail — a live prohibition — into the repo.
  local held = {}
  local function flush_held(dest)
    vim.list_extend(dest, held)
    held = {}
  end

  for _, line in ipairs(lines) do
    local name = line:match("^feature%s+(.+)$")
    if name then
      flush_held(map_lines)
      current_feature = vim.trim(name)
      in_never = false
      map_lines[#map_lines + 1] = line
    elseif line:match("^  never%s*$") then
      flush_held(map_lines)
      in_never = true
      if current_feature and not emitted_holdout_header[current_feature] then
        holdout_lines[#holdout_lines + 1] = "feature " .. current_feature
        emitted_holdout_header[current_feature] = true
      end
      holdout_lines[#holdout_lines + 1] = line
    elseif in_never and line:match("^%s*$") then
      held[#held + 1] = line
    elseif in_never and line:match("^    %S") then
      flush_held(holdout_lines) -- the blanks were interior after all
      holdout_lines[#holdout_lines + 1] = line
      never_count = never_count + 1
    else
      flush_held(map_lines)
      in_never = false
      map_lines[#map_lines + 1] = line
    end
  end
  flush_held(map_lines)
  -- A feature that exists ONLY in the holdout leaves a bare header line in
  -- map_lines with no content; keep it — harmless, and round-trip stable.
  return map_lines, holdout_lines, never_count
end

-- ---------------------------------------------------------------------------
-- buffer + rendering
-- ---------------------------------------------------------------------------

local function combined_map()
  local mapmod = require("scry.map")
  state.kinds = mapmod.kinds_for(state.root)
  return mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), state.kinds)
end

--- Render report verdicts into the glass buffer as extmarks.
function M.render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local mapmod = require("scry.map")
  local debt = require("scry.debt")
  local feat = require("scry.feature")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  -- Peeked diffs go too: a render follows the moments the diff itself moves
  -- (a cast landing, a write, a discard's reload), and a stale diff shown as
  -- current is worse than pressing <Tab> again.
  vim.api.nvim_buf_clear_namespace(state.buf, diff_ns, 0, -1)

  state.map = combined_map()
  state.debt = debt.count(state.map, state.report, state.root)

  -- THE GLOSS (`g?`). Virtual lines, off by default — see scry.explain for
  -- why this is not the starter block returning.
  local explain = require("scry.explain")
  local function gloss(lnum, text)
    if text then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, lnum - 1, 0, {
        virt_lines = { { { "      ? " .. text, "ScryEvidence" } } },
      })
    end
  end
  if explain.showing() then
    -- The header's own gloss hangs off the buffer's opening blank line,
    -- which exists precisely because there is no room above line 1.
    gloss(
      1,
      explain.header(
        state.debt,
        require("scry.advice").best(state.map, state.report, require("scry.project").resolve(state.root))
      )
    )
  end

  -- The header lives in the winbar (see scry.debt.winbar and M.winbar
  -- below), not in an extmark. It used to be virt_lines above line 1, which
  -- Neovim does not draw — there is no room above a buffer's first line —
  -- so it was invisible on precisely the map a new user opens first.

  -- THE VERDICT COLUMN.
  --
  -- Verdicts used to begin three spaces after whatever the line happened to
  -- say, which left the one thing a reader scans for scattered across the
  -- width of the buffer. They are a column now — every verdict on the page
  -- starts at the same screen cell, so the states read as a strip you can
  -- run your eye down rather than as annotations you have to find.
  --
  -- This is quickfix-pro's argument about the display line, applied to the
  -- glass: alignment is not decoration, it is what makes a list scannable.
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local function width_of(lnum)
    return vim.fn.strdisplaywidth(lines[lnum] or "")
  end
  local widest = 0
  for _, feature in ipairs(state.map.features) do
    widest = math.max(widest, width_of(feature.lnum))
  end
  for _, claim in ipairs(state.map.claims) do
    widest = math.max(widest, width_of(claim.lnum))
  end
  -- Capped, so one long prohibition regex cannot push every verdict off the
  -- right of the window. A line past the cap simply gets the minimum gap.
  local COLUMN = math.min(widest + 3, 64)
  local function pad(lnum)
    local gap = COLUMN - width_of(lnum)
    return (" "):rep(gap >= 2 and gap or 2)
  end

  -- The path a member resolves to, when the row does not already say it.
  local function path_of(claim)
    local p = mapmod.claim_path(claim, state.kinds)
    if p and claim.target:find(p, 1, true) ~= 1 then
      return p
    end
    return nil
  end

  -- A SECOND COLUMN, for the verdicts, because a member row now says two
  -- things: where it lands, and whether it holds. Ragged, those read as one
  -- run-on annotation; aligned, they are two columns you can run an eye
  -- down — the same argument that put the first one in a column.
  --
  -- It collapses onto the first when no member needs a path, so a map of
  -- plain paths does not pay for a column it never fills.
  local widest_path = 0
  for _, claim in ipairs(state.map.claims) do
    local p = path_of(claim)
    if p then
      widest_path = math.max(widest_path, COLUMN + vim.fn.strdisplaywidth(p))
    end
  end
  local VERDICT_AT = widest_path > 0 and math.min(widest_path + 3, 96) or COLUMN

  -- EVERY OPEN ROW SAYS WHAT IT IS.
  --
  -- A member's verdict used to be withheld when every member of the feature
  -- agreed — the same "render what varies" rule the folded map follows. That
  -- rule was measured on the SCAN: fourteen features, one state between them,
  -- three hundred characters of pure texture. It does not transfer down here.
  --
  -- At a member row the reader is not scanning for anomalies, they are
  -- VERIFYING THE MEMBERS: is that the right file, is it really there. Each
  -- row is a separate assertion, and a silent row makes you recall a
  -- rendering rule before you can interpret it.
  --
  -- So: open rows always carry their verdict. The folded scan still drops what
  -- repeats (see foldtext), because there the density argument is real.

  -- Each feature carries the state its evidence adds up to. This is the line
  -- a reader actually scans, so it gets the strongest rendering on the page.
  state.survey = survey(state.map, state.report, state.root)
  for _, feature in ipairs(state.map.features) do
    local v = feat.verdict(feature, state.report, state.root)
    -- THE OPEN FEATURE LINE ALWAYS SAYS ITS STATE. It used to be withheld
    -- when every feature in the map read the same — which, in a map with ONE
    -- feature, is always, so the only row on the page said nothing at all.
    -- The scan view still drops what repeats (see foldtext); an open row does
    -- not, because a reader working a feature needs to know where it stands
    -- without reconstructing why the space beside it is empty.
    local words = v and v.label or ""
    -- On EVERY line the feature is opened on, not just the first: a feature
    -- may be re-opened later in the map to add members, and a header row
    -- with no verdict beside it reads as a feature nothing checked.
    for _, at in ipairs(feature.lnums or { feature.lnum }) do
      local mark = {}
      if words ~= "" then
        mark.virt_text = { { pad(at) .. words, FEATURE_HL[v.state] or "ScryEvidence" } }
        mark.virt_text_pos = "eol"
      end
      -- BREATHING ROOM, rendered rather than written. Features arrive from a
      -- drafting pass with no blank line between them, and a map is not
      -- improved by scry editing someone's file to add whitespace — so the
      -- separator is a virtual line, and the file stays exactly what its
      -- author typed.
      --
      -- Not above line 1: Neovim has no room to draw there, and a mark that
      -- exists without drawing is the bug this buffer's header once had.
      -- Not where the author already left a blank line either — two blank
      -- rows is not twice the breathing room, it is a gap.
      if at > 1 and vim.trim(lines[at - 1] or "") ~= "" then
        mark.virt_lines = { { { "", "NonText" } } }
        mark.virt_lines_above = true
      end
      if mark.virt_text or mark.virt_lines then
        pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, at - 1, 0, mark)
      end
      if explain.showing() then
        gloss(at, explain.feature(v))
        if #(feature.desc or {}) > 0 then
          gloss(at + 1, explain.description())
        end
      end
    end

    -- AND AIR BETWEEN THE SENTENCE AND THE FILE LIST. What a feature IS and
    -- what it is MADE OF are the two altitudes this whole buffer is built
    -- around, and they were running together as one block of text.
    --
    -- Attached BELOW the last line of the description rather than above the
    -- first member, because the members are a fold: a mark above a closed
    -- fold's first line is not drawn (Neovim has nowhere to put it), so the
    -- gap would have vanished in exactly the default view.
    local first = feature.lnums and feature.lnums[1] or feature.lnum
    for i = first + 1, #lines do
      if lines[i]:match("^feature%s") then
        break
      end
      if M.is_member_line(lines[i], state.kinds) then
        -- Only when there is something between the name and the members. A
        -- feature with no description reads fine tight.
        if i > first + 1 then
          pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, i - 2, 0, {
            virt_lines = { { { "", "NonText" } } },
          })
        end
        break
      end
    end
  end

  for _, claim in ipairs(state.map.claims) do
    local parts = {}
    local v = state.report and state.report.verdicts[mapmod.claim_id(claim)]

    -- WHERE THIS MEMBER LANDS, when the row does not already say. A kind
    -- names a thing and its probe knows the file — `route [slug]` IS
    -- src/pages/[slug].astro — and without it the reader is being asked to
    -- agree that a capability is made of four files while looking at two of
    -- them.
    --
    -- Shown only where it differs from what is written. `def
    -- src/layouts/Layout.astro` already names its file, and printing the
    -- path beside a row that IS the path is texture. Not merely "different
    -- from the target" either: `def lua/auth.lua:create_session` resolves to
    -- `lua/auth.lua`, which the row already opens with.
    local used = width_of(claim.lnum)
    local path = path_of(claim)
    if path then
      parts[#parts + 1] = { pad(claim.lnum) .. path, "ScryPath" }
      used = COLUMN + vim.fn.strdisplaywidth(path)
    end

    -- The verdict lands in its own column whether or not a path came first,
    -- so the two read as columns rather than as one run-on annotation.
    if v then
      local hl = (v.status == "backed" or v.status == "clean") and "ScryBacked"
        or (v.status == "unchecked" and "ScryUnchecked" or "ScryDiverged")
      local gap = VERDICT_AT - used
      parts[#parts + 1] = { (" "):rep(gap >= 2 and gap or 2) .. v.label, hl }
    end

    -- WHAT THE PLAN SAYS ABOUT THIS ROW, as a word rather than a reading
    -- exercise. The states were there — a note plus `✓ present` meant change,
    -- a note plus `✗ absent` meant create — but a reader had to cross-check
    -- two columns and the prose to know which kind of row they were on.
    -- After the cast the same slot carries the closure: what actually
    -- happened, and `skipped` for a planned member the cast never touched.
    local cpath = mapmod.claim_path(claim, state.kinds)
    local pmark = require("scry.plan").mark(
      claim,
      cpath,
      cpath ~= nil and vim.fn.filereadable(state.root .. "/" .. cpath) == 1
    )
    if pmark then
      local WORD = {
        change = { "~ change", "ScryPlanChange" },
        create = { "+ create", "ScryPlanCreate" },
        changed = { "✓ changed", "ScryBacked" },
        created = { "✓ created", "ScryBacked" },
        skipped = { "✗ skipped", "ScryBuilding" },
      }
      local w = WORD[pmark]
      parts[#parts + 1] = { (#parts > 0 and " · " or pad(claim.lnum)) .. w[1], w[2] }
    end
    if explain.showing() then
      gloss(claim.lnum, explain.member(v))
    end

    if #parts > 0 then
      local mark = { virt_text = parts, virt_text_pos = "eol" }
      if v and v.status == "violated" and v.evidence then
        mark.virt_lines = {}
        for _, e in ipairs(v.evidence) do
          -- lnum 0 means the evidence has no line to point at (a run's
          -- output, not a match in a file); showing ":0" would invent one.
          local where = e.lnum > 0 and ("%s:%d → %s"):format(e.path, e.lnum, e.text) or e.text
          mark.virt_lines[#mark.virt_lines + 1] = { { "        └ " .. where, "ScryEvidence" } }
        end
      end
      pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, claim.lnum - 1, 0, mark)
    end
  end

  -- A winbar expression is only re-evaluated on redraw, and a check settles
  -- asynchronously — so the counts appeared only once some keypress
  -- happened to force one. On a fast machine that looks like a missing
  -- header; on a slow one it looks like a header that arrives when you
  -- touch the keyboard.
  pcall(vim.cmd, "redrawstatus!")
end

--- The winbar's content for the window this is evaluated in.
---
--- Evaluated per redraw rather than assigned, so it answers for whatever
--- window asks and empties itself the moment that window stops showing the
--- glass. Returning the counts from `state` means it refreshes with every
--- check without anything having to remember to update it.
---@return string
function M.winbar()
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf and state.debt) then
    return ""
  end
  local action = M.next_action()
  -- vim.fn.winwidth, not nvim_win_get_width. A winbar expression is
  -- evaluated in a restricted context where the API call fails, and a
  -- failing expression renders as NOTHING — the option was set, the
  -- function returned a correct string when called by hand, and the bar was
  -- blank. pcall on top so a future restriction degrades to an unfitted
  -- line rather than to an empty one.
  local ok, width = pcall(vim.fn.winwidth, 0)
  return require("scry.debt").winbar(state.debt, state.report and state.report.at, ok and width or nil, action)
end

--- What to do next, from where the cursor is.
---
--- The header used to say `+ to draft` and nothing else, forever. An engineer
--- who opened the glass on a capability they had just described, read
--- `✓ 5 files exist`, and looked for what to do next was told to draft more
--- features — while the operator that would actually build the thing was not
--- named anywhere on the screen.
---
--- Never nil when the glass has content: "I do not know what to do here" is
--- the state this exists to remove.
---@return string?
function M.next_action()
  local ok, recover = pcall(require, "scry.recover")
  if ok and recover.passing() then
    return "+ to stop drafting"
  end
  local lnum = (pcall(vim.fn.line, ".") and vim.fn.line(".")) or 0
  local feature
  for _, f in ipairs((state.map or {}).features or {}) do
    for _, at in ipairs(f.lnums or { f.lnum }) do
      if at <= lnum and (not feature or at > feature.at) then
        feature = { f = f, at = at }
      end
    end
  end
  if feature then
    if #feature.f.claims == 0 then
      -- Named and made of nothing.
      return "+ to find its files"
    end
    local pending = require("scry.plan").pending
    if pending and pending.feature == feature.f.name and not pending.outcomes then
      return "~ to build the plan"
    end
    return "~ to change it"
  end
  if (state.debt or {}).unclaimed and state.debt.unclaimed > 0 then
    return "+ to draft"
  end
  if #((state.map or {}).features or {}) == 0 then
    -- An empty map has no noun to aim at, so the way in is the intent.
    return ":Scry <what you want to do>"
  end
  -- Features exist and the cursor is not on one. Naming the verb and where it
  -- applies beats saying nothing: "I do not know what to do here" is the
  -- state this exists to remove, and it was the state a fully described
  -- project sat in permanently.
  return "~ on a feature to change it"
end

-- The first `feature` line, memoized per change. The fold expression is
-- evaluated once per line per redraw, and the "is there a feature above me"
-- question used to walk backwards from every one of them — quadratic in the
-- length of the map, on the hot path.
local first_feature = { tick = -1, lnum = nil }
local function first_feature_lnum()
  local tick = vim.b.changedtick
  if first_feature.tick ~= tick then
    first_feature.tick, first_feature.lnum = tick, nil
    for i = 1, vim.fn.line("$") do
      if vim.fn.getline(i):match("^feature%s") then
        first_feature.lnum = i
        break
      end
    end
  end
  return first_feature.lnum
end

--- Fold expression: ONE level, one fold per feature.
---
--- There was a second level for a while — the members folded into a bar
--- under the description, so the default view was titles and sentences with
--- the file lists tucked away. It read well in a screenshot and badly in
--- use: `<Tab>` near a member collapsed the thing you were working on into
--- a `▍▍▍▍` row, which summarized precisely the rows the plan had just
--- annotated. A fold that hides the work is not a zoom, it is a surprise.
---
--- So members are simply visible. The one fold left is the feature, which
--- is the scan view: `zM` for one row per feature, `zR` to open the map.
---
--- Lines before the first feature are level 0, which keeps a stale header
--- or a drafting block from being swallowed into the first feature's fold.
---@param lnum integer
---@return string
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^feature%s") then
    return ">1"
  end
  local first = first_feature_lnum()
  if not first or lnum < first then
    return "0"
  end
  return "1"
end

--- The feature whose block a line falls in.
---@param at integer
---@return scry.Feature?
local function owning_feature(at)
  local found
  for _, f in ipairs((state.map or {}).features or {}) do
    for _, l in ipairs(f.lnums or { f.lnum }) do
      if l <= at and (not found or l > found.at) then
        found = { feature = f, at = l }
      end
    end
  end
  return found and found.feature or nil
end

--- The fold's one line when it is closed: one feature per row, the scan.
---
--- The feature row is ALIGNED, because it is a column of states and a column
--- is the only reason to put them one under another. It says how many
--- MEMBERS, not how many lines: a line count measures the prose someone
--- wrote; a member count is how much of the product the feature is made of,
--- which is the question the number was standing in for.
---@param at integer? the fold's first line; defaults to Neovim's v:foldstart,
---       which only has a value while a fold is actually being drawn — so a
---       spec (or anything wanting one line's rendering) passes it in.
---@return table[]
function M.foldtext(at)
  at = at or vim.v.foldstart

  -- The `feature ` keyword is dropped. Every folded row IS a feature, so it
  -- repeated the same eight columns down the whole page and told a reader
  -- nothing they could not see — and those columns are what pushed the
  -- longest names past the alignment cap.
  local function summary(lnum)
    return (vim.fn.getline(lnum):gsub("^feature%s+", ""))
  end
  local line = summary(at)
  local feature = owning_feature(at)

  local widest = 0
  for _, f in ipairs((state.map or {}).features or {}) do
    widest = math.max(widest, vim.fn.strdisplaywidth(summary(f.lnum)))
  end
  local column = math.min(widest + 3, 72)
  local gap = column - vim.fn.strdisplaywidth(line)
  local pad = (" "):rep(gap >= 2 and gap or 2)

  local verdict = feature and state.report and require("scry.feature").verdict(feature, state.report, state.root)
  local n = feature and #feature.claims or 0

  -- CHUNKS, not a string. A folded line is drawn in one highlight — Folded
  -- — so returning text made the whole closed map a single gray, which is
  -- most of what a reader looks at. Neovim lets 'foldtext' return
  -- {text, group} pairs, so the name, the state and the count keep the
  -- colors they have when the fold is open, and the state column can be
  -- read by color before it is read by word.
  local hl = verdict and (FEATURE_HL[verdict.state] or "ScryEvidence") or "ScryEvidence"
  local mark = verdict and ATTENTION[verdict.state] or nil

  local out = {
    -- Column one: the state, or nothing at all.
    { mark and (" " .. mark .. " ") or "   ", hl },
    { line, "ScryFeatureName" },
  }

  -- The verdict's words only where they discriminate, and with the glyph
  -- removed because it is in column one now — saying it twice says it once.
  local words = verdict_words(verdict, (state.survey or {}).uniform)
  if words ~= "" then
    words = words:gsub("^%S+%s+", "")
  end
  if words ~= "" then
    out[#out + 1] = { pad, "Folded" }
    out[#out + 1] = { words, hl }
  elseif n > 0 then
    out[#out + 1] = { pad, "Folded" }
  end

  if n > 0 then
    out[#out + 1] = { "  " .. bar(n), "ScryIntent" }
  end
  return out
end

-- A GLANCE AT THE DIFF, WITHOUT LEAVING THE MAP.
--
-- The review tab (|scry-compose|) is the full walk; this is the look you
-- take before deciding to walk. `<Tab>` on a member whose file has an
-- unsaved change unfolds the diff right under the row — capped, because a
-- forty-hunk diff inline in the map stops being a glance — and `<Tab>`
-- again puts it away.
local diff_ns = vim.api.nvim_create_namespace("scry.diff")

-- Enough to judge a small change whole and to recognize a big one.
local DIFF_LINES = 20

--- Toggle an inline diff under the member at the cursor.
---@return boolean handled false when there is nothing here to diff
function M.toggle_diff()
  if not state.root then
    return false
  end
  local here = vim.api.nvim_win_get_cursor(0)[1]
  local claim
  for _, c in ipairs((state.map or {}).claims or {}) do
    if c.lnum == here then
      claim = c
    end
  end
  if not claim then
    return false
  end
  local cpath = require("scry.map").claim_path(claim, state.kinds)
  if not cpath then
    return false
  end

  -- Already showing: put it away.
  local marks = vim.api.nvim_buf_get_extmarks(state.buf, diff_ns, { here - 1, 0 }, { here - 1, -1 }, {})
  if #marks > 0 then
    for _, m in ipairs(marks) do
      vim.api.nvim_buf_del_extmark(state.buf, diff_ns, m[1])
    end
    return true
  end

  -- The diff only exists between an unsaved buffer and the disk. Before the
  -- cast a `~ change` row has nothing to show yet; after `:w` the change IS
  -- the disk. Neither is an error — there is just nothing here to peek at.
  local full = state.root .. "/" .. cpath
  local buf = vim.fn.bufnr(full)
  if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modified then
    return false
  end

  local disk = vim.fn.filereadable(full) == 1 and (table.concat(vim.fn.readfile(full), "\n") .. "\n") or ""
  local now = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  -- vim.text.diff is this API's current name; vim.diff its old one.
  local difffn = (vim.text and vim.text.diff) or vim.diff
  local unified = difffn(disk, now, { ctxlen = 2 })
  if not unified or unified == "" then
    return false
  end

  local rows = {}
  local all = vim.split(unified, "\n", { plain = true, trimempty = true })
  for i = 1, math.min(#all, DIFF_LINES) do
    local line = all[i]
    local lead = line:sub(1, 1)
    local hl = (lead == "+" and "Added") or (lead == "-" and "Removed") or "ScryEvidence"
    rows[#rows + 1] = { { "      " .. line, hl } }
  end
  if #all > DIFF_LINES then
    rows[#rows + 1] = {
      {
        ("      … %d more line%s — the review tab after a cast walks all of it"):format(
          #all - DIFF_LINES,
          #all - DIFF_LINES == 1 and "" or "s"
        ),
        "ScryEvidence",
      },
    }
  end
  vim.api.nvim_buf_set_extmark(state.buf, diff_ns, here - 1, 0, { virt_lines = rows })
  return true
end

--- Jump to the next or previous feature whose verdict wants something.
---
--- Deliberately does not wrap. A motion that silently starts over hides the
--- fact that you have seen everything, and "no more" is the answer you most
--- want at the end of a pass.
---@param dir 1|-1
---@return boolean moved
function M.wants_attention(dir)
  if not (state.map and state.report) then
    return false
  end
  local feat = require("scry.feature")
  local here = vim.api.nvim_win_get_cursor(0)[1]
  local best
  for _, f in ipairs(state.map.features or {}) do
    local v = feat.verdict(f, state.report, state.root)
    if v and ATTENTION[v.state] then
      for _, at in ipairs(f.lnums or { f.lnum }) do
        -- Not `dir > 0 and at > here or at < here`. That is the Lua
        -- ternary idiom, and it breaks precisely when the middle term is
        -- false: `(false) or (at < here)` then answers the question for the
        -- OTHER direction, so ]d past the last one silently wrapped
        -- backwards — which is the one behavior this deliberately does not
        -- have.
        local ahead
        if dir > 0 then
          ahead = at > here
        else
          ahead = at < here
        end
        if ahead and (not best or (dir > 0 and at < best) or (dir < 0 and at > best)) then
          best = at
        end
      end
    end
  end
  if not best then
    vim.notify(
      ("[scry] no %s feature wants anything"):format(dir > 0 and "later" or "earlier"),
      vim.log.levels.INFO
    )
    return false
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { best, 0 })
  return true
end

--- Window-local options for a window showing the glass. Window-local, so
--- they have to be re-applied every time the buffer enters a window rather
--- than set once at creation.
---@param buf integer
function M.window_options(buf)
  local function apply()
    if vim.api.nvim_get_current_buf() ~= buf then
      return
    end
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'scry.glass'.foldexpr(v:lnum)"
    vim.wo.foldtext = "v:lua.require'scry.glass'.foldtext()"
    -- OPEN on arrival. Members are simply visible — the fold that tucked
    -- them into a bar under the description summarized exactly the rows the
    -- plan annotates, and collapsed them under your cursor. The one fold is
    -- the feature itself: `zM` for the one-row-per-feature scan, `zR` back.
    vim.wo.foldlevel = 1
    vim.wo.foldenable = true
    -- No dot leader. Vim fills a fold line to the window edge, and at this
    -- density it drew eighty columns of `·` after every feature — the
    -- loudest thing on a page whose whole job is a quiet list.
    vim.wo.fillchars = "fold: "
    -- A WRAPPED LINE KEEPS ITS INDENT. Indentation is this buffer's grammar,
    -- so a continuation starting in column one reads as a new line at the
    -- outermost level — a feature's description looked like it had become
    -- something else halfway through a sentence. `linebreak` too, because
    -- prose broken mid-word is prose you re-read.
    vim.wo.breakindent = true
    vim.wo.linebreak = true
    -- One feature per row means the row IS the unit of attention.
    vim.wo.cursorline = true
    vim.wo.winbar = "%{%v:lua.require'scry.glass'.winbar()%}"
  end
  apply()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = apply,
  })
  -- An empty winbar still costs a screen row, so it is removed outright when
  -- this window moves on to another buffer rather than left evaluating to "".
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buf,
    callback = function()
      pcall(function()
        vim.wo.winbar = ""
      end)
    end,
  })
end

--- Run reflexion over the glass content and re-render.
---@param cb fun()? called after render
function M.check(cb)
  if not state.buf then
    return
  end
  local m = combined_map()
  require("scry.check").run(m, { root = state.root, resolver = require("scry.resolver").get() }, function(report)
    state.report = report
    M.render()
    if cb then
      cb()
    end
    -- THE CEILING COMES TO YOU. Scry knows exactly what is limiting these
    -- answers — which claims stopped at the text rung, that nothing has been
    -- run — and used to say none of it unless you went looking. Once per
    -- project per session, ranked by what it would buy here.
    require("scry.advice").offer(state.root, m, report, require("scry.project").resolve(state.root))
    -- REACH, IN THE BACKGROUND. Divergence counts a file undescribed when no
    -- member names it, but a file a feature's entry points REACH is described
    -- by that feature — so until this has run, the unclaimed number is an
    -- upper bound. It used to require putting the cursor on each feature and
    -- running a command, which meant in practice it never ran at all.
    --
    -- Asynchronous and cached: it never blocks looking, a second look costs
    -- nothing, and the header says `reach pending` until the answer is in
    -- rather than presenting the reach-free count as the whole truth.
    local reach = require("scry.reach")
    if state.root and reach.progress.state ~= "done" then
      reach.refresh(state.root, m, function(changed)
        if changed and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
          M.render()
        end
      end)
    end
  end)
end

--- Open (or focus) the glass for `root`, compose it, and check.
---@param root string?
function M.open(root)
  root = root or vim.fn.getcwd()

  -- WHAT SCRY CANNOT WORK WITHOUT, before anything opens. Without ripgrep
  -- every prohibition, reference and divergence check errors, and the glass
  -- fills with `– resolver error` — which reads as a broken project rather
  -- than a missing tool. A `never` that has silently stopped being checked is
  -- the most dangerous state this thing has, so it refuses instead.
  local missing, how = require("scry.advice").crucial()
  if missing then
    error(("[scry] %s\n        %s"):format(missing, how), 0)
  end

  local config = require("scry.project").resolve(root or state.root)

  local function focus(buf)
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_win_set_buf(0, buf)
    end
  end

  local reusing = state.buf and vim.api.nvim_buf_is_valid(state.buf)
  if reusing and state.root == root then
    focus(state.buf)
    M.check()
    return
  end
  if reusing and vim.bo[state.buf].modified then
    -- state.root is what M.write() writes to. Re-pointing it at a new root
    -- while the buffer still holds another project's beliefs would save those
    -- beliefs over this project's map — silently, and irreversibly. Refuse,
    -- and leave the user looking at the buffer that has the unsaved work.
    focus(state.buf)
    vim.notify(
      ("[scry] the glass has unsaved changes for %s — :w or :bwipeout it before opening %s"):format(
        vim.fn.fnamemodify(state.root, ":~"),
        vim.fn.fnamemodify(root, ":~")
      ),
      vim.log.levels.WARN
    )
    return
  end

  local map_lines = require("scry.map").load(root .. "/" .. config.map_path).lines
  local holdout_lines = require("scry.holdout").load(root, config).lines
  -- AN EMPTY MAP OPENS EMPTY. There used to be a block of instructions
  -- here for a project with no map. It was prose, so it parsed fine and
  -- never left — it sat above every feature that arrived after it and was
  -- written into .scry/map.scry on the first `:w`, which is a file of
  -- someone's beliefs about their product with a tutorial at the top.
  --
  -- The header already says what to do (`+ to draft`), and `:Scry {intent}`
  -- is the way in that does not need reading about. See |scry-aim|.
  local composed = M.compose(map_lines, holdout_lines)

  -- ONE BLANK LINE AT THE TOP, and a real one. The gap between features is
  -- virtual, but there is no room above a buffer's first line for Neovim to
  -- draw in — probed twice — so the only way to have air under the header is
  -- to put a line there.
  --
  -- It costs a leading blank in `.scry/map.scry`, which is the honest price
  -- and a small one. Added only when the first line is not already blank, or
  -- every save-and-reopen would grow another.
  if #composed > 0 and vim.trim(composed[1]) ~= "" then
    table.insert(composed, 1, "")
  end

  local buf = state.buf
  if reusing then
    -- Same buffer, different project: replace the content, then re-point the
    -- root. The order is the invariant — state.root always describes what is
    -- actually in the buffer.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, composed)
    state.report = nil
    state.debt = nil
  else
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "scry://glass")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, composed)
    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    -- The syntax cannot tell a member from a description by shape, so it
    -- is handed the kinds in force — the same set map.parse takes, and for
    -- the same reason. Set BEFORE filetype, since that is what sources it.
    local names = {}
    for name in pairs(require("scry.map").kinds_for(root)) do
      names[#names + 1] = vim.pesc and name or name
    end
    table.sort(names)
    vim.b[buf].scry_kinds = table.concat(names, "\\|")
    vim.bo[buf].filetype = "scry"
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        M.write()
      end,
    })
    -- One verb everywhere: conjurer's global :Conjure casts over a range;
    -- this buffer-local one shadows it in the glass only, and casts the
    -- claim under the cursor instead.
    vim.api.nvim_buf_create_user_command(buf, "Conjure", function()
      require("scry.cascade").start()
    end, { desc = "Conjure the claim under the cursor" })

    -- <CR> is the only mapping, and it means "take me to what this line is
    -- about" — the code for a claim, and for a feature line the fold, since
    -- what a feature line is about is its own body. Nothing else is bound:
    -- this is a normal, writable buffer and its editing keys have to stay
    -- exactly the editing keys.
    -- <Tab> opens and closes a feature's FILE LIST — the thing the default
    -- view keeps folded and the thing you open a feature for.
    --
    -- Not plain `za`. The cursor is normally on a feature's name or in its
    -- description, and the fold there is the feature itself, so `za` would
    -- collapse the very sentence you were reading. This reaches down to the
    -- members instead, which is what the key means.
    -- <Tab> peeks the diff on a member with an unsaved change, and on a
    -- feature line it folds the feature to its scan row. Anywhere else it
    -- does NOTHING, on purpose: it used to fall through to a fold toggle,
    -- which collapsed the members you were reading into a summary bar the
    -- moment there was no diff to show. A key that sometimes hides your
    -- work is worse than a key that sometimes does nothing.
    vim.keymap.set("n", "<Tab>", function()
      if M.toggle_diff() then
        return
      end
      if vim.fn.getline("."):match("^feature%s") then
        pcall(vim.cmd, "normal! za")
      end
    end, { buffer = buf, desc = "scry: peek the diff here, or fold this feature" })

    -- ]d AND [d — TO THE NEXT THING THAT WANTS YOU.
    --
    -- The obvious way to surface what needs attention is to group by state
    -- with headings. It is the wrong move here, because the buffer IS the
    -- file: grouping means reordering, and reordering means rewriting
    -- someone's document to suit a view of it.
    --
    -- Vim's answer to "take me to the one that matters" was never sorting.
    -- It was motions. The document keeps the order its author gave it, a
    -- motion does the work grouping would have done, and it composes with
    -- everything else — `]d~` is "fix the next broken thing", and `.`
    -- repeats that.
    --
    -- ]d/[d are Neovim's jump-to-#define, which is C-specific and useless
    -- here, so the buffer-local override costs nothing.
    for lhs, dir in pairs({ ["]d"] = 1, ["[d"] = -1 }) do
      vim.keymap.set("n", lhs, function()
        M.wants_attention(dir)
      end, { buffer = buf, desc = "scry: " .. (dir > 0 and "next" or "previous") .. " feature that wants you" })
    end

    -- `+` DRAFTS WHAT IS MISSING, and stops a pass in flight.
    --
    -- The affordance belongs in the buffer rather than in a command you have
    -- to have read about: the header says how many files nothing describes,
    -- and the key to do something about it sits next to the number.
    --
    -- `+` because this buffer is edited. `d` would read best and cost `dd`
    -- and `dw` on your own prose, which is not a trade worth making for one
    -- gesture. `+` is only a synonym for <CR>'s motion, which the glass has
    -- already taken, so nothing is lost — and it reads as "add what is not
    -- here yet".
    -- SCOPED BY WHERE THE CURSOR IS. `+` means "add what is not here yet",
    -- and what that is depends on what you are looking at.
    --
    -- On a feature with nothing under it, what is missing is its MEMBERS —
    -- you typed the capability in your own words and the files it is made of
    -- are scry's job to find (|scry-members|). Typing member paths by hand
    -- meant knowing the layout before you were allowed to describe the
    -- product, which is backwards, and it was the last hand-typed step in
    -- the loop.
    --
    -- Anywhere else, what is missing is features for the files nothing
    -- describes. Same verb, one key.
    vim.keymap.set("n", "+", function()
      local recover = require("scry.recover")
      if recover.passing() then
        recover.stop()
        return
      end
      if require("scry.members").at_cursor() then
        return
      end
      recover.start()
    end, { buffer = buf, desc = "scry: fill in what is missing here (again to stop a pass)" })

    -- `~` IS THE OPERATOR, the same key conjurer uses on a text object.
    -- There it rewrites a region; here the noun is a whole capability and
    -- the change lands across every file it is made of. Same verb, coarser
    -- grain — which is the only reason this buffer exists.
    vim.keymap.set("n", "~", function()
      require("scry.compose").start()
    end, { buffer = buf, desc = "scry: cast an intent across this whole feature" })

    -- `g?` EXPLAINS THIS BUFFER, which is what `g?` means in every plugin
    -- that has an opinion. It also answers the question the render-what-varies
    -- rule creates: a silent row is quiet because everything agreed, and
    -- until you have learned that, silence and "nothing ran" look identical.
    vim.keymap.set("n", "g?", function()
      require("scry.explain").toggle()
    end, { buffer = buf, desc = "scry: explain what this buffer is telling you" })

    vim.keymap.set("n", "<CR>", function()
      if vim.fn.getline("."):match("^feature%s") then
        pcall(vim.cmd, "normal! za")
        return
      end
      if not require("scry.locate").open() then
        vim.notify("[scry] nothing under the cursor to open", vim.log.levels.WARN)
      end
    end, { buffer = buf, desc = "scry: open what this line is about" })
  end
  vim.bo[buf].modified = false
  state.buf = buf
  state.root = root
  -- Before window_options, which installs the fold expression: a fold
  -- evaluated without the project's kinds reads every member as prose and
  -- folds nothing.
  state.kinds = require("scry.map").kinds_for(root)
  -- focus FIRST. window_options only applies to a window already showing
  -- the glass, so applying before the buffer is in one silently did
  -- nothing on the very first :Scry — the run everyone sees.
  focus(buf)
  M.window_options(buf)
  M.check()
end

--- Write the glass: split and save both files, notify the routing, re-check.
function M.write()
  local config = require("scry.project").resolve(state.root)
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local map_lines, holdout_lines, never_count = M.split(lines)
  vim.fn.mkdir(vim.fn.fnamemodify(state.root .. "/" .. config.map_path, ":h"), "p")
  vim.fn.writefile(map_lines, state.root .. "/" .. config.map_path)
  require("scry.holdout").save(state.root, config, holdout_lines)
  vim.bo[state.buf].modified = false
  -- Writing the map is accepting it: the plan's words have done their job.
  require("scry.plan").clear()
  local where = require("scry.holdout").in_repo(state.root, config) and "IN the repo (weaker holdout)"
    or "outside the repo"
  vim.notify(
    ("[scry] map → %s · %d never-claim%s → holdout (%s)"):format(
      config.map_path,
      never_count,
      never_count == 1 and "" or "s",
      where
    )
  )
  M.check()
end

return M
