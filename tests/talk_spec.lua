-- The conversation: summoned, aimed, dismissed — never the primary surface.
-- Driven against `cat` standing in for the claude terminal, which echoes
-- what it is sent, so the one-line aim is observable.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

require("scry").setup({ talk = { cmd = { "cat" } } })
local talk = require("scry.talk")
local glass = require("scry.glass")

-- A project with a map, opened in the glass, cursor on a feature.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.scry", "p")
vim.fn.writefile({
  "feature you can export a month as CSV",
  "  One row per expense, header first.",
  "  module lua/csv.lua",
}, root .. "/.scry/map.scry")
glass.open(root)
H.ok(H.wait(function()
  return glass._state.report ~= nil
end, 8000), "glass opened")
vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- the feature line (after the top blank)

-- K asks: vim.ui.input is stubbed the way the cascade specs stub it.
local orig_input = vim.ui.input
vim.ui.input = function(_, cb)
  cb("who calls this?")
end
local glass_win = vim.api.nvim_get_current_win()
talk.ask()
vim.ui.input = orig_input

H.ok(talk._state.buf ~= nil, "the conversation exists")
H.eq(vim.bo[talk._state.buf].buftype, "terminal", "and it is a real terminal")
-- ...and it is NOT the glass. A terminal jobstart converts the current
-- buffer, and the split opened showing the glass — without a fresh buffer
-- first, the conversation ate the map.
H.ok(talk._state.buf ~= glass._state.buf, "the conversation did not eat the glass")
H.eq(vim.bo[glass._state.buf].buftype, "acwrite", "which is still the map's buffer")
H.ok(vim.api.nvim_get_current_win() ~= glass_win, "focus moved to the conversation to read the answer")
vim.cmd("stopinsert")

-- The aim is ONE LINE naming the feature and the map file — the model has
-- the repo and reads the files itself. The terminal wraps long lines at
-- its width, so the screen is reflowed before asserting.
local function screen()
  -- Raw join: the wrap point can fall on a real space, which a trailing-
  -- whitespace trim would eat.
  return table.concat(vim.api.nvim_buf_get_lines(talk._state.buf, 0, -1, false), "")
end
H.ok(H.wait(function()
  return screen():find("you can export a month as CSV", 1, true) ~= nil
end, 8000), "the feature's name reached the conversation")
H.ok(screen():find(".scry/map.scry", 1, true) ~= nil, "with the map's path")
H.ok(screen():find("who calls this?", 1, true) ~= nil, "and the question")
H.eq(screen():find("One row per expense", 1, true), nil, "no content is ferried — an address is")

-- A GITIGNORED MAP IS INVISIBLE TO SEARCH, and the first real conversation
-- proved it: the model globbed, found nothing, and reported the file did
-- not exist. When the map is ignored, the aim says so.
vim.fn.system({ "git", "-C", root, "init", "-q" })
vim.fn.writefile({ ".scry/" }, root .. "/.gitignore")
vim.ui.input = function(_, cb)
  cb("still there?")
end
talk.ask()
vim.ui.input = orig_input
vim.cmd("stopinsert")
H.ok(H.wait(function()
  return screen():find("gitignored", 1, true) ~= nil
end, 8000), "an ignored map's aim warns that searching will not find it")
H.ok(screen():find(root .. "/.scry/map.scry", 1, true) ~= nil, "and the path is absolute, so a direct read just works")

-- Toggle: hide, same conversation back.
local buf_before = talk._state.buf
talk.toggle()
local hidden = true
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == buf_before then
    hidden = false
  end
end
H.ok(hidden, "toggle hides the split")
talk.toggle()
vim.cmd("stopinsert")
H.eq(talk._state.buf, buf_before, "and reveals the SAME exchange, not a new one")

H.done("talk_spec PASS")
