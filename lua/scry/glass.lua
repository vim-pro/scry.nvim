-- The glass: one editable buffer composed from two files — the in-repo map
-- and the out-of-repo holdout — with computed verdicts rendered as extmarks
-- and NEVER stored. Writing the glass parses the buffer and routes blocks
-- back: never-sections to the holdout, everything else to the map, with a
-- notification so storage routing is never silent.
local M = {}

local ns = vim.api.nvim_create_namespace("scry.glass")

-- The palette. Every group is a `default link`, so a colorscheme that
-- defines any of them wins and nothing here has to know about colors.
--
-- Two principles decide the links. Verdicts borrow the DIAGNOSTIC groups,
-- because a verdict is the same kind of thing a diagnostic is and every
-- scheme has already made those legible against its own background. The
-- buffer's own text borrows SYNTAX groups, because the map is a language
-- and reads best when it is colored like one.
--
-- `untouched` is deliberately the quietest thing on the page. It is the
-- state every claim starts in — a freshly drafted map is nothing but
-- untouched claims — so rendering it as a warning would paint the whole
-- buffer with an alarm that means "new".
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
  ScryStamp = "NonText",

  -- the grammar
  ScryKeyword = "Statement", -- the word `feature`
  -- NOT Title. A feature's name is the sentence you read, and there are as
  -- many of them as there are features — a closed map is nothing but names,
  -- so coloring them as headings painted the entire page one color. Bold and
  -- otherwise untouched: structure without a hue, and the only colors left on
  -- a folded map are the ones that mean something.
  ScryFeatureName = false,
  ScrySection = "Type", -- contains / calls / exercises
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
  ScryDiverged = "DiagnosticError",
  ScryUnchecked = "DiagnosticHint",
  ScryUntouched = "NonText",

  -- feature states, which get their own groups because a reader scans this
  -- column first and the seven states are not four
  ScryDone = "DiagnosticOk",
  ScryBroken = "DiagnosticError",
  ScryBuilding = "DiagnosticWarn",
  ScryUnread = "DiagnosticInfo",
  ScryTodo = "DiagnosticHint",
}
for group, target in pairs(HL) do
  if target == false then
    vim.api.nvim_set_hl(0, group, { bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end
-- Named for ratification, which no longer exists. Kept linked so a config
-- that styled it does not silently lose its color.
vim.api.nvim_set_hl(0, "ScryUnratified", { link = "ScryUntouched", default = true })

-- A feature's state to the group that renders it. Module scope because BOTH
-- views need it: render() puts it at the end of an open feature line, and
-- foldtext() puts it on the closed one — and the closed map is the view a
-- reader spends most of their time in.
local FEATURE_HL = {
  done = "ScryDone",
  broken = "ScryBroken",
  partial = "ScryBuilding",
  unread = "ScryUnread",
  absent = "ScryTodo",
  unevidenced = "ScryTodo",
  unknown = "ScryUnchecked",
}

-- WHICH STATES WANT YOU. Column one is the most valuable space on the
-- screen — a scan reads the first characters of each line and little else —
-- and it was spent on the first letter of a sentence, fourteen times over.
-- It carries state instead, and carries nothing when a feature is fine.
--
-- Silence is the healthy reading. `unread` is not an alarm: it is what every
-- claim in a freshly drafted map is, and marking all of them would mark
-- none of them.
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
--- header already said `14 unread · 50 backed · 0 missing · 0 violated`.
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

-- Session state: one glass per project root.
local state = {
  root = nil,
  buf = nil,
  map = nil, -- combined (map + holdout) parsed view of the glass buffer
  report = nil,
  debt = nil,
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
  return mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
end

--- Render report verdicts into the glass buffer as extmarks.
function M.render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local mapmod = require("scry.map")
  local prov = require("scry.provenance")
  local debt = require("scry.debt")
  local feat = require("scry.feature")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  state.map = combined_map()
  state.debt = debt.count(state.map, state.report, state.root)

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

  -- Each feature carries the state its evidence adds up to. This is the line
  -- a reader actually scans, so it gets the strongest rendering on the page.
  state.survey = survey(state.map, state.report, state.root)
  for _, feature in ipairs(state.map.features) do
    local v = feat.verdict(feature, state.report, state.root)
    -- On EVERY line the feature is opened on, not just the first: a feature
    -- may be re-opened later in the map to add members, and a header row
    -- with no verdict beside it reads as a feature nothing checked.
    for _, at in ipairs(feature.lnums or { feature.lnum }) do
      pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, at - 1, 0, {
        virt_text = { { pad(at) .. v.label, FEATURE_HL[v.state] or "ScryEvidence" } },
        virt_text_pos = "eol",
      })
    end
  end

  for _, claim in ipairs(state.map.claims) do
    local parts = {}
    local v = state.report and state.report.verdicts[mapmod.claim_id(claim)]
    if v then
      local hl = (v.status == "backed" or v.status == "clean") and "ScryBacked"
        or (v.status == "unchecked" and "ScryUnchecked" or "ScryDiverged")
      parts[#parts + 1] = { pad(claim.lnum) .. v.label, hl }
    end
    if not (state.root and prov.owned(state.root, claim)) then
      parts[#parts + 1] = { (#parts > 0 and " · ∅" or pad(claim.lnum) .. "∅"), "ScryUntouched" }
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
  -- vim.fn.winwidth, not nvim_win_get_width. A winbar expression is
  -- evaluated in a restricted context where the API call fails, and a
  -- failing expression renders as NOTHING — the option was set, the
  -- function returned a correct string when called by hand, and the bar was
  -- blank. pcall on top so a future restriction degrades to an unfitted
  -- line rather than to an empty one.
  local ok, width = pcall(vim.fn.winwidth, 0)
  return require("scry.debt").winbar(state.debt, state.report and state.report.at, ok and width or nil)
end

--- The starter map, for a project that has none.
---
--- EVERY LINE OF IT IS PROSE, and a spec pins that. An earlier version
--- opened on a real feature whose one claim pointed at
--- `path/to/file.lua:symbol`, so the first thing anyone ever saw was two red
--- verdicts against a file that was never meant to exist — scry reporting,
--- accurately, on its own placeholder. Accurate and useless: nothing there
--- was a belief anyone held, so nothing there was worth checking.
---
--- It leads with `+` because that is the honest answer to an empty map
--- over a full repository, and its example is written at sea level (see
--- |scry-altitude|) so the shape you copy is the right shape.
---@return string[]
function M.starter()
  return {
      "-- No map yet. Press + to have a conjurer write the first pass over",
      "-- the files nothing describes; everything it writes lands unread, and",
      "-- stays unread until you have read it.",
      "--",
      "-- Or write one yourself and delete this. Indentation is the grammar:",
      "--",
      "--   feature a reader can follow a link someone sent them",
      "--     Prose is never checked. Say what the feature is for, and why it",
      "--     is one feature rather than two.",
      "--",
      "--     contains",
      "--       lua/links.lua:resolve    a definition that exists right now",
      "--       lua/links.lua            when the file defines nothing nameable",
      "--",
      "-- A feature is one thing someone can accomplish, named the way they",
      "-- would name it — not \"the auth system\", which swallows the product,",
      "-- and not \"validate the token\", which is what a claim already is.",
      "-- :h scry-altitude",
    }
end

--- Fold expression: one fold per feature.
---
--- A real map is long — scry's own is 12 features over 130 lines — and the
--- reason you opened it is usually one of them. Features are the fold level
--- because features are the unit: everything under one, prose and claims
--- alike, belongs to it. Lines before the first feature are level 0, which
--- keeps a stale header or a drafting block from being swallowed into the
--- first feature's fold.
---@param lnum integer
---@return string
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^feature%s") then
    return ">1"
  end
  -- Before the first feature there is nothing to belong to.
  for i = lnum - 1, 1, -1 do
    if vim.fn.getline(i):match("^feature%s") then
      return "1"
    end
  end
  return "0"
end

--- The fold's one line when it is closed — the whole map, one feature per
--- row, and the view a reader spends most of their time in.
---
--- ALIGNED, because it is a column of states and a column is the only
--- reason to put them one under another. The open view aligns its verdicts
--- and the closed view did not, so the states drifted with the length of
--- each feature's name — ragged in exactly the view that exists to be
--- scanned.
---
--- It says how many MEMBERS, not how many lines. A line count measures the
--- prose someone wrote; a member count is how much of the product the
--- feature is made of, which is the question the number was standing in for.
---@return string
---@param at integer? the fold's first line; defaults to Neovim's v:foldstart,
---       which only has a value while a fold is actually being drawn — so a
---       spec (or anything wanting one line's rendering) passes it in.
function M.foldtext(at)
  -- The `feature ` keyword is dropped. Every folded row IS a feature, so it
  -- repeated the same eight columns down the whole page and told a reader
  -- nothing they could not see — and those columns are what pushed the
  -- longest names past the alignment cap.
  local function summary(lnum)
    return (vim.fn.getline(lnum):gsub("^feature%s+", ""))
  end
  at = at or vim.v.foldstart
  local line = summary(at)
  local feature
  for _, f in ipairs((state.map or {}).features or {}) do
    for _, l in ipairs(f.lnums or { f.lnum }) do
      if l == at then
        feature = f
      end
    end
  end

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

  -- The verdict's words only where they discriminate: not when every feature
  -- in the map reads the same, and not to spell out `5 of 5`, which says
  -- only that nothing is missing — which is what saying nothing says.
  local survey_ = state.survey or { uniform = false }
  local partial = verdict and verdict.total and verdict.backed and verdict.backed < verdict.total
  if verdict and (partial or not survey_.uniform) then
    -- The label with its glyph removed, because the glyph is in column one
    -- now and saying it twice says it once. And with a trailing `N of N`
    -- removed when nothing is missing: "3 of 3" is a longer way of writing
    -- what the absence of a fraction already writes.
    --
    -- Both are edits to the engine's own wording rather than a substitute
    -- for it. The glass may not say something stronger than the verdict
    -- said, so it does not compose a word of its own here.
    local words = verdict.label:gsub("^%S+%s+", "")
    if not partial then
      words = words:gsub("%s*%(?%d+ of %d+%)?$", "")
    end
    if words ~= "" then
      out[#out + 1] = { pad, "Folded" }
      out[#out + 1] = { words, hl }
    elseif n > 0 then
      out[#out + 1] = { pad, "Folded" }
    end
  elseif n > 0 then
    out[#out + 1] = { pad, "Folded" }
  end

  if n > 0 then
    out[#out + 1] = { "  " .. bar(n), "ScryIntent" }
  end
  return out
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
    -- CLOSED on arrival. A map's features are the thing you scan; their
    -- members are what you open one for. Fifty claims in view at once is
    -- the same wall of detail the altitude work was about, just rendered
    -- instead of authored.
    vim.wo.foldlevel = 0
    vim.wo.foldenable = true
    -- No dot leader. Vim fills a fold line to the window edge, and at this
    -- density it drew eighty columns of `·` after every feature — the
    -- loudest thing on a page whose whole job is a quiet list.
    vim.wo.fillchars = "fold: "
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
    -- turn state transitions into trail events (cascaded → settled) before
    -- rendering, so ownership appears the moment the work comes true
    require("scry.provenance").sync(state.root, m, report)
    M.render()
    if cb then
      cb()
    end
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
  local composed = M.compose(map_lines, holdout_lines)
  if #composed == 0 then
    composed = M.starter()
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
    -- <Tab> opens and closes a feature. Features are what you scan and
    -- their members are what you open one FOR, so the map arrives closed
    -- and this is how it lets you in.
    vim.keymap.set("n", "<Tab>", function()
      pcall(vim.cmd, "normal! za")
    end, { buffer = buf, desc = "scry: expand or collapse this feature" })

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
    vim.keymap.set("n", "+", function()
      local recover = require("scry.recover")
      if recover.passing() then
        recover.stop()
      else
        recover.start()
      end
    end, { buffer = buf, desc = "scry: draft the files nothing describes (again to stop)" })

    -- `~` IS THE OPERATOR, the same key conjurer uses on a text object.
    -- There it rewrites a region; here the noun is a whole capability and
    -- the change lands across every file it is made of. Same verb, coarser
    -- grain — which is the only reason this buffer exists.
    vim.keymap.set("n", "~", function()
      require("scry.compose").start()
    end, { buffer = buf, desc = "scry: cast an intent across this whole feature" })

    vim.keymap.set("n", "<CR>", function()
      if vim.fn.getline("."):match("^feature%s") then
        pcall(vim.cmd, "normal! za")
        return
      end
      if not require("scry.locate").open() then
        vim.notify("[scry] nothing under the cursor to open", vim.log.levels.WARN)
      end
    end, { buffer = buf, desc = "scry: open what this line is about" })
    -- Claims that appear under the user's own edits are AUTHORED — that is
    -- the whole ownership gesture. state.map is the renderer's snapshot, so
    -- scry's own writes never register as authorship.
    require("scry.provenance").watch(buf, function()
      return state.root
    end, function()
      return state.map
    end)
  end
  vim.bo[buf].modified = false
  state.buf = buf
  state.root = root
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
