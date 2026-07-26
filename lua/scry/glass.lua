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

-- Interleave holdout never-blocks into their concerns: after a concern's
-- last line in the map, before the next concern header.
---@param map_lines string[]
---@param holdout_lines string[]
---@return string[]
function M.compose(map_lines, holdout_lines)
  local mapmod = require("scry.map")
  local hold = mapmod.parse(holdout_lines)

  -- Collect each holdout concern's never block lines (header excluded).
  local never_blocks = {} -- name -> lines
  do
    local current, collecting = nil, false
    for _, line in ipairs(holdout_lines) do
      local name = line:match("^# (.+)$")
      if name then
        current = vim.trim(name)
        collecting = false
      elseif current then
        if line:match("^  never%s*$") then
          collecting = true
          never_blocks[current] = never_blocks[current] or {}
          table.insert(never_blocks[current], line)
        elseif collecting and line:match("^    %S") then
          table.insert(never_blocks[current], line)
        else
          collecting = false
        end
      end
    end
  end

  local out = {}
  local m = mapmod.parse(map_lines)
  local emitted = {}
  for i, line in ipairs(map_lines) do
    -- before the NEXT concern header (or EOF), flush the current concern's nevers
    local name = line:match("^# (.+)$")
    if name then
      -- find which concern (if any) we're leaving
      for _, c in ipairs(m.concerns) do
        if c.lnum < i and not emitted[c.name] and never_blocks[vim.trim(c.name)] then
          vim.list_extend(out, never_blocks[c.name])
          emitted[c.name] = true
        end
      end
    end
    out[#out + 1] = line
  end
  for _, c in ipairs(m.concerns) do
    if not emitted[c.name] and never_blocks[c.name] then
      vim.list_extend(out, never_blocks[c.name])
      emitted[c.name] = true
    end
  end
  -- holdout concerns with no map concern: append whole
  for name, block in pairs(never_blocks) do
    if not emitted[name] and not mapmod.concern(m, name) then
      out[#out + 1] = "# " .. name
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
  local current_concern = nil
  local emitted_holdout_header = {}
  local in_never = false
  local never_count = 0

  for _, line in ipairs(lines) do
    local name = line:match("^# (.+)$")
    if name then
      current_concern = vim.trim(name)
      in_never = false
      map_lines[#map_lines + 1] = line
    elseif line:match("^  never%s*$") then
      in_never = true
      if current_concern and not emitted_holdout_header[current_concern] then
        holdout_lines[#holdout_lines + 1] = "# " .. current_concern
        emitted_holdout_header[current_concern] = true
      end
      holdout_lines[#holdout_lines + 1] = line
    elseif in_never and line:match("^    %S") then
      holdout_lines[#holdout_lines + 1] = line
      never_count = never_count + 1
    else
      if in_never and not (line:match("^%s*$")) then
        in_never = false
      elseif in_never and line:match("^%s*$") then
        in_never = false
        -- a blank after a never block belongs to the map layout
      end
      map_lines[#map_lines + 1] = line
    end
  end
  -- A concern that exists ONLY in the holdout leaves a bare "# name" line in
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
  local ratify = require("scry.ratify")
  local debt = require("scry.debt")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  state.map = combined_map()
  state.debt = debt.count(state.map, state.report)

  -- header (virt_lines above line 1)
  pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, 0, 0, {
    virt_lines = { { { debt.header(state.debt, state.report and state.report.at), "ScryHeader" } } },
    virt_lines_above = true,
  })

  for _, claim in ipairs(state.map.claims) do
    local parts = {}
    local v = state.report and state.report.verdicts[mapmod.claim_id(claim)]
    if v then
      local hl = (v.status == "backed" or v.status == "clean") and "ScryBacked"
        or (v.status == "unchecked" and "ScryEvidence" or "ScryDiverged")
      parts[#parts + 1] = { "   " .. v.label, hl }
    end
    if not ratify.ratified(claim) then
      parts[#parts + 1] = { " · ∅ unratified", "ScryUnratified" }
    end
    if #parts > 0 then
      local mark = { virt_text = parts, virt_text_pos = "eol" }
      if v and v.status == "violated" and v.evidence then
        mark.virt_lines = {}
        for _, e in ipairs(v.evidence) do
          mark.virt_lines[#mark.virt_lines + 1] = {
            { ("        └ %s:%d → %s"):format(e.path, e.lnum, e.text), "ScryEvidence" },
          }
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
  state.root = root

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local win = vim.fn.bufwinid(state.buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_win_set_buf(0, state.buf)
    end
    M.check()
    return
  end

  local map_lines = require("scry.map").load(root .. "/" .. config.map_path).lines
  local holdout_lines = require("scry.holdout").load(root, config).lines
  local composed = M.compose(map_lines, holdout_lines)
  if #composed == 0 then
    composed = { "# my project", "  files lua/**/*.lua", "", "  contains", "    path/to/file.lua:symbol" }
  end

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "scry://glass")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, composed)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "scry"
  vim.bo[buf].modified = false
  state.buf = buf

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.write()
    end,
  })

  vim.api.nvim_win_set_buf(0, buf)
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

--- Ratify the claim on the cursor line (glass only).
function M.ratify_current()
  if vim.api.nvim_get_current_buf() ~= state.buf then
    vim.notify("[scry] :ScryRatify works in the glass buffer", vim.log.levels.WARN)
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  state.map = combined_map()
  for _, claim in ipairs(state.map.claims) do
    if claim.lnum == lnum then
      local ratify = require("scry.ratify")
      local line = ratify.stamp(state.map, claim, ratify.author(require("scry").config))
      vim.api.nvim_buf_set_lines(state.buf, lnum - 1, lnum, false, { line })
      M.render()
      vim.notify(("[scry] ratified: %s"):format(claim.target))
      return
    end
  end
  vim.notify("[scry] no claim on this line", vim.log.levels.WARN)
end

return M
