-- A conversation, summoned — never the surface you live on.
--
-- Some work is "explain this to me before I aim anything," and the answer
-- is not a chat panel rebuilt inside the glass. It is the conversation you
-- already use — the claude terminal app — in a split, launched at the
-- project root so it has the repository, and AIMED the way everything else
-- here is aimed: `K` on a feature sends one line naming it and the map
-- file, and the model reads the actual files itself. Scry ferries an
-- address, not content.
--
-- One conversation per session. The terminal buffer persists hidden; K or
-- :ScryTalk reveal the same exchange, and <C-w>p puts you back in the
-- glass. The split is a peek, like <Tab>'s diff — the glass stays home.
local M = {}

local state = { buf = nil, chan = nil }

local function alive()
  return state.buf
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.chan
    and pcall(vim.fn.jobpid, state.chan)
end

--- The window currently showing the conversation, if any.
local function window()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return nil
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == state.buf then
      return w
    end
  end
  return nil
end

--- Ensure the conversation exists and is visible; return to focus it.
---@param root string
---@return integer? win
local function reveal(root)
  local win = window()
  if win then
    return win
  end
  local prev = vim.api.nvim_get_current_win()
  vim.cmd("botright 15split")
  win = vim.api.nvim_get_current_win()
  if alive() then
    vim.api.nvim_win_set_buf(win, state.buf)
  else
    -- A FRESH BUFFER FIRST. The split shows whatever the previous window
    -- showed — the glass — and a terminal jobstart converts the CURRENT
    -- buffer. Without this line it converted the glass itself.
    vim.cmd("enew")
    local cmd = ((require("scry").config or {}).talk or {}).cmd or { "claude" }
    state.chan = vim.fn.jobstart(cmd, { term = true, cwd = root })
    if state.chan <= 0 then
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_set_current_win(prev)
      vim.notify(("[scry] could not start `%s`"):format(table.concat(cmd, " ")), vim.log.levels.ERROR)
      return nil
    end
    state.buf = vim.api.nvim_get_current_buf()
    vim.bo[state.buf].buflisted = false
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = state.buf,
      once = true,
      callback = function()
        state.buf, state.chan = nil, nil
      end,
    })
  end
  vim.api.nvim_set_current_win(prev)
  return win
end

--- Show or hide the conversation, keeping it running either way.
function M.toggle()
  local win = window()
  if win then
    vim.api.nvim_win_hide(win)
    return
  end
  local root = require("scry.glass")._state.root or vim.fn.getcwd()
  win = reveal(root)
  if win then
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end
end

--- `K` in the glass: ask about the feature under the cursor.
---
--- The question travels as ONE LINE naming the feature and the map file.
--- The conversation runs in the project root, so the model opens the map
--- and the members itself — the same reason a cascade sends targets rather
--- than prose.
function M.ask()
  local feature, gstate = require("scry.compose").at_cursor()
  local root = (gstate and gstate.root) or require("scry.glass")._state.root or vim.fn.getcwd()
  local about = feature
      and ("the feature `%s` in %s"):format(feature.name, require("scry.project").resolve(root).map_path)
    or ("the feature list in %s"):format(require("scry.project").resolve(root).map_path)

  vim.ui.input({ prompt = "Ask: " }, function(question)
    local win = reveal(root)
    if not win then
      return
    end
    if question and vim.trim(question) ~= "" then
      vim.fn.chansend(state.chan, ("About %s — %s\n"):format(about, vim.trim(question)))
    end
    vim.api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end)
end

M._state = state -- for specs

return M
