-- The glass: one editable buffer composed from two files — the in-repo map
-- and the out-of-repo holdout — with computed verdicts rendered as extmarks
-- and NEVER stored. Writing the glass parses the buffer and routes blocks
-- back: never-sections to the holdout, everything else to the map, with a
-- notification so storage routing is never silent.
local M = {}

local ns = vim.api.nvim_create_namespace("scry.glass")

-- The palette. Every group is a `default link`, so a colorscheme that
-- defines any of them wins and nothing here has to know about colours.
--
-- Two principles decide the links. Verdicts borrow the DIAGNOSTIC groups,
-- because a verdict is the same kind of thing a diagnostic is and every
-- scheme has already made those legible against its own background. The
-- buffer's own text borrows SYNTAX groups, because the map is a language
-- and reads best when it is coloured like one.
--
-- `untouched` is deliberately the quietest thing on the page. It is the
-- state every claim starts in — a freshly drafted map is nothing but
-- untouched claims — so rendering it as a warning would paint the whole
-- buffer with an alarm that means "new".
local HL = {
  -- the page
  ScryHeader = "Title",
  ScryEvidence = "Comment",
  ScryProse = "Comment",
  ScryStamp = "NonText",

  -- the grammar
  ScryKeyword = "Statement", -- the word `feature`
  ScryFeatureName = "Title", -- what the feature is called
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
  vim.api.nvim_set_hl(0, group, { link = target, default = true })
end
-- Named for ratification, which no longer exists. Kept linked so a config
-- that styled it does not silently lose its colour.
vim.api.nvim_set_hl(0, "ScryUnratified", { link = "ScryUntouched", default = true })

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
  local m = mapmod.parse(map_lines)
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
  return require("scry.map").parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false))
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

  -- header (virt_lines above line 1); it is two lines now — features, then
  -- the claim-level evidence behind them
  local header = {}
  for _, line in ipairs(vim.split(debt.header(state.debt, state.report and state.report.at), "\n", { plain = true })) do
    header[#header + 1] = { { line, "ScryHeader" } }
  end
  pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, 0, 0, {
    virt_lines = header,
    virt_lines_above = true,
  })

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
  local FEATURE_HL = {
    done = "ScryDone",
    broken = "ScryBroken",
    partial = "ScryBuilding",
    unread = "ScryUnread",
    absent = "ScryTodo",
    unevidenced = "ScryTodo",
    unknown = "ScryUnchecked",
  }
  for _, feature in ipairs(state.map.features) do
    local v = feat.verdict(feature, state.report, state.root)
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, feature.lnum - 1, 0, {
      virt_text = { { pad(feature.lnum) .. v.label, FEATURE_HL[v.state] or "ScryEvidence" } },
      virt_text_pos = "eol",
    })
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
    -- The starter map. It has to be VALID grammar: whatever is here is the
    -- first thing anyone sees, and a template the parser reads as prose
    -- teaches a syntax that does not exist. (It did exactly that until the
    -- feature layer landed and this line kept seeding `# my project` and a
    -- `files` glob, neither of which has been grammar for some time.)
    composed = {
      "feature name one thing a user can accomplish",
      "  Prose is never checked. Say what the feature is for, and why it is",
      "  one feature rather than two.",
      "",
      "  contains",
      "    path/to/file.lua:symbol",
      "",
      "-- :Scry checks this against the code every time you look.",
      "-- :h scry-altitude for what belongs on a feature line.",
    }
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

  focus(buf)
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
