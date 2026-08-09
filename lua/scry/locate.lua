-- Where a claim points, and how to get there.
--
-- The glass is the surface you work FROM, and until now there was no way to
-- get from it to the work: you read a path off a claim line and typed it
-- into :edit yourself. A map you cannot leave is a document, not a window.
--
-- THE ORDER OF PREFERENCE IS THE HONESTY. Evidence first, always: if the
-- report has a line for this claim, that is a place the engine actually
-- looked and found something, so it is the truest destination available. A
-- VIOLATED prohibition jumps to the violation, which is the single most
-- useful jump scry can offer.
--
-- Only when there is no evidence does it fall back to the claim's own text,
-- and the symbol's line is resolved by the same treesitter query that
-- decided `✓ defined` — so a jump can never land somewhere the verdict did
-- not mean. Failing that, line 1 of the file, which at least gets you there.
--
-- Nothing here guesses. A claim with no evidence and no path (a `never`
-- pattern that is holding) has no destination, and says so rather than
-- inventing one.
local M = {}

--- Where this claim points.
---@param claim scry.Claim
---@param verdict scry.Verdict?
---@param root string
---@return { path: string, lnum: integer, why: string }?
function M.target(claim, verdict, root)
  -- 1) Evidence: somewhere an engine actually looked.
  if verdict and verdict.evidence then
    for _, e in ipairs(verdict.evidence) do
      -- lnum 0 means the evidence is run output, not a place in a file.
      if e.path and e.lnum and e.lnum > 0 then
        return { path = e.path, lnum = e.lnum, why = "evidence" }
      end
    end
  end

  -- 2) The claim's own path, if it names one.
  local path = require("scry.map").claim_path(claim, require("scry.map").kinds_for(root))
  if not path then
    return nil
  end

  -- 3) The symbol's line, from the query that decided the verdict.
  if claim.kind == "def" then
    local symbol = claim.target:match("^.-:([%w_.]+)$")
    if symbol then
      -- No pcall. ts_rg.locate already answers nil for an unreadable or
      -- unparseable file, so wrapping it only ever hid a real error — which
      -- it did: this silently degraded to "file" for every claim while
      -- locate() referenced a `read` that was not yet in scope.
      local found = require("scry.resolvers.ts_rg").locate(root, path, symbol)
      if found then
        return { path = path, lnum = found, why = "definition" }
      end
    end
  end

  return { path = path, lnum = 1, why = "file" }
end

-- The window a jump should land in.
--
-- Not the glass's own window: the point of the jump is to have the map and
-- the code both in front of you. Prefer a window already showing something
-- else, so repeated jumps reuse one window instead of shredding the layout;
-- split only when the glass is all there is.
---@param glass_win integer
---@return integer
local function destination_window(glass_win)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= glass_win and vim.api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
  vim.cmd("vsplit")
  return vim.api.nvim_get_current_win()
end

--- Jump to whatever the claim under the cursor points at.
function M.open()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf and state.root) then
    return false
  end
  local mapmod = require("scry.map")
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))

  local claim
  for _, c in ipairs(map_.claims) do
    if c.lnum == lnum then
      claim = c
      break
    end
  end
  if not claim then
    return false
  end

  local verdict = state.report and state.report.verdicts[mapmod.claim_id(claim)]
  local target = M.target(claim, verdict, state.root)
  if not target then
    vim.notify(("[scry] %s names no place to go yet"):format(claim.target), vim.log.levels.WARN)
    return true
  end

  local abs = target.path
  if not abs:match("^/") then
    abs = state.root .. "/" .. abs
  end
  if vim.fn.filereadable(abs) == 0 then
    -- An absent claim is the normal state of work not yet done, so this is
    -- information rather than a failure.
    vim.notify(("[scry] %s does not exist yet"):format(target.path), vim.log.levels.WARN)
    return true
  end

  local glass_win = vim.api.nvim_get_current_win()
  local win = destination_window(glass_win)
  vim.api.nvim_set_current_win(win)
  vim.cmd("edit " .. vim.fn.fnameescape(abs))
  pcall(vim.api.nvim_win_set_cursor, win, { target.lnum, 0 })
  vim.cmd("normal! zz")
  return true
end

return M
