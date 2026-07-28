-- The glass: one editable buffer composed from two files — the in-repo map
-- and the out-of-repo holdout — with computed verdicts rendered as extmarks
-- and NEVER stored. Writing the glass parses the buffer and routes blocks
-- back: never-sections to the holdout, everything else to the map, with a
-- notification so storage routing is never silent.
local M = {}

local ns = vim.api.nvim_create_namespace("scry.glass")

vim.api.nvim_set_hl(0, "ScryBacked", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "ScryDiverged", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "ScryUnratified", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "ScryEvidence", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "ScryHeader", { link = "Title", default = true })

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

  -- Each feature carries the state its evidence adds up to. This is the line
  -- a reader actually scans, so it gets the strongest rendering on the page.
  for _, feature in ipairs(state.map.features) do
    local v = feat.verdict(feature, state.report)
    local hl = (v.state == "done" and "ScryBacked")
      or (v.state == "broken" and "ScryDiverged")
      or (v.state == "partial" and "ScryUnratified")
      or (v.state == "absent" and "ScryDiverged")
      or "ScryEvidence"
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, feature.lnum - 1, 0, {
      virt_text = { { "   " .. v.label, hl } },
      virt_text_pos = "eol",
    })
  end

  for _, claim in ipairs(state.map.claims) do
    local parts = {}
    local v = state.report and state.report.verdicts[mapmod.claim_id(claim)]
    if v then
      local hl = (v.status == "backed" or v.status == "clean") and "ScryBacked"
        or (v.status == "unchecked" and "ScryEvidence" or "ScryDiverged")
      parts[#parts + 1] = { "   " .. v.label, hl }
    end
    if not (state.root and prov.owned(state.root, claim)) then
      parts[#parts + 1] = { " · ∅ untouched", "ScryUnratified" }
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
  local config = require("scry").config

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
    composed = { "# my project", "  files lua/**/*.lua", "", "  contains", "    path/to/file.lua:symbol" }
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
  local config = require("scry").config
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
