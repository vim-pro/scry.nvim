-- The glass: compose interleaves holdout nevers into their concerns; :write
-- splits blocks back to the right files with a notification; verdicts render
-- as extmarks; ratify stamps the cursor line.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local glass = require("scry.glass")

-- 1) compose: nevers land inside their concern, before the next header.
local composed = glass.compose({
  "# auth",
  "  files lua/auth.lua",
  "  contains",
  "    lua/auth.lua:create_session",
  "",
  "# billing",
  "  files lua/billing.lua",
}, {
  "# auth",
  "  never",
  "    logging\\.debug",
})
local text = table.concat(composed, "\n")
local auth_pos = text:find("# auth", 1, true)
local never_pos = text:find("  never", 1, true)
local billing_pos = text:find("# billing", 1, true)
H.ok(never_pos and auth_pos < never_pos and never_pos < billing_pos, "never block interleaved inside its concern")

-- 2) split: the inverse routes blocks to the right files.
local map_lines, holdout_lines, count = glass.split(composed)
H.eq(count, 1, "one never claim routed")
H.ok(table.concat(map_lines, "\n"):find("never", 1, true) == nil, "map side has no never block")
H.ok(table.concat(holdout_lines, "\n"):find("logging\\.debug", 1, true) ~= nil, "holdout side has the pattern")
H.ok(table.concat(holdout_lines, "\n"):find("# auth", 1, true) ~= nil, "holdout keeps the concern header")
-- compose(split(x)) is stable
local recomposed = glass.compose(map_lines, holdout_lines)
H.eq(table.concat(recomposed, "\n"), text, "compose∘split is identity on composed input")

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
H.ok(virt[row_of("create_session")]:find("∅ unratified", 1, true) ~= nil, "unratified marker rendered")
H.ok(virt[row_of("refresh_token")]:find("✗ absent", 1, true) ~= nil, "absent verdict rendered")
H.ok(virt[row_of("logging\\.debug")]:find("VIOLATED", 1, true) ~= nil, "violation rendered")
H.ok(virt[row_of("logging\\.debug")]:find("lua/auth.lua:9", 1, true) ~= nil, "evidence line rendered")
H.ok(virt[0] ~= nil and virt[0]:find("claims", 1, true) ~= nil, "header present")
H.ok(virt[0]:find("files on disk", 1, true) ~= nil, "header carries the disk caveat")

-- 4) ratify the cursor claim, then hand-edit it → unratified returns
vim.api.nvim_win_set_cursor(0, { row_of("create_session") + 1, 0 })
require("scry.glass").ratify_current()
local stamped = vim.api.nvim_buf_get_lines(buf, row_of("create_session"), row_of("create_session") + 1, false)[1]
H.ok(stamped:find("-- @", 1, true) ~= nil, "stamp written into the buffer line")
local virt2 = H.virt_by_row(buf, ns)
H.ok(virt2[row_of("create_session")]:find("∅ unratified", 1, true) == nil, "ratified claim loses the marker")

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
H.ok(saved_map:find("-- @", 1, true) ~= nil, "stamp persisted to the map file")
H.ok(saved_map:find("never", 1, true) == nil, "no never block leaked into the repo map")
H.ok(saved_hold:find("logging\\.debug", 1, true) ~= nil, "holdout file holds the patterns")

H.done("glass_spec PASS")
