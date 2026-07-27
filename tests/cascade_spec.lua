-- The thesis test. An absent claim becomes quickfix work, the conjurer casts
-- it, and the prohibition it never saw catches the result.
--
-- The load-bearing assertion: walk EVERY string that leaves scry and prove no
-- never-pattern text rides along. Independence isn't hoped for here, it's
-- checked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local cascade = require("scry.cascade")
local holdout = require("scry.holdout")

-- A workspace copy of the fixture, so casts can really edit files.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
vim.fn.mkdir(work .. "/.scry", "p")
for _, f in ipairs({ "auth.lua", "store.lua", "logging.lua" }) do
  vim.fn.writefile(vim.fn.readfile(H.fixture .. "/lua/" .. f), work .. "/lua/" .. f)
end
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/map.scry"), work .. "/.scry/map.scry")
require("scry").setup({ holdout_path = work .. "/holdout.scry" })
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/holdout.scry"), work .. "/holdout.scry")

local m = map.load(work .. "/.scry/map.scry")
local absent
for _, c in ipairs(m.claims) do
  if c.target == "lua/auth.lua:refresh_token" then
    absent = c
  end
end
H.ok(absent ~= nil, "found the absent claim to cascade")

-- 1) build() is pure and shaped right
local built = cascade.build(absent, "define refresh_token using the session store")
H.eq(built.file, "lua/auth.lua", "target file extracted")
H.eq(built.symbol, "refresh_token", "target symbol extracted")
H.eq(#built.items, 1, "one seeded entry")
H.eq(built.items[1].user_data.scry.concern, "auth", "entry carries scry's own user_data")
H.eq(built.items[1].user_data.scry.target, absent.target, "and the claim it came from")
H.eq(#vim.fn.getqflist({ items = 1 }).items, 0, "build() wrote nothing to the list (pure)")

-- 2) THE WITHHOLDING WALK: no never-pattern text in anything outgoing.
local hold = map.load(work .. "/holdout.scry")
local never_targets = {}
for _, c in ipairs(hold.claims) do
  if c.kind == "never" then
    never_targets[#never_targets + 1] = c.target
  end
end
H.ok(#never_targets >= 2, "the holdout actually has prohibitions to withhold")
local outgoing = { built.intent, built.items[1].text, built.items[1].filename, tostring(built.symbol) }
for _, pattern in ipairs(never_targets) do
  for _, s in ipairs(outgoing) do
    H.ok(not s:find(pattern, 1, true), ("no %q in outgoing %q"):format(pattern, s))
  end
  -- also the un-escaped, human form of the pattern (logging.debug vs logging\.debug)
  local plain = pattern:gsub("\\", "")
  for _, s in ipairs(outgoing) do
    H.ok(not s:find(plain, 1, true), ("no %q (plain form) in outgoing %q"):format(plain, s))
  end
end

-- 3) the tripwire fires on a poisoned payload
local poisoned = false
local ok = pcall(function()
  holdout.assert_clean({ "please avoid logging\\.debug here" }, never_targets)
end)
poisoned = not ok
H.eq(poisoned, true, "assert_clean errors when a never-pattern appears in an outgoing string")
H.eq(pcall(holdout.assert_clean, outgoing, never_targets), true, "and passes on the real payload")

-- 4) cascade only accepts contains claims
local never_claim = hold.claims[1]
H.eq(pcall(cascade.build, never_claim, "x"), false, "cascade refuses a never claim")

-- 5) seed the real list (no handoff), then simulate the conjurer writing a
-- VIOLATING implementation and saving: the withheld prohibition catches it.
cascade.seed(work, absent, "define refresh_token", false)
local items = vim.fn.getqflist({ items = 1 }).items
H.eq(#items, 1, "list seeded")
H.ok(items[1].text:find("refresh_token", 1, true) ~= nil, "entry text names the symbol")
H.ok(items[1].text:find("logging", 1, true) == nil, "entry text carries no prohibition text")

-- the "conjured" result: correct-looking, and it logs a token (the trap the
-- generator never saw)
local auth = work .. "/lua/auth.lua"
local lines = vim.fn.readfile(auth)
local insert_at
for i, l in ipairs(lines) do
  if l:find("function M.validate_token", 1, true) then
    insert_at = i - 1
  end
end
table.insert(lines, insert_at + 1, "")
table.insert(lines, insert_at + 2, "function M.refresh_token(raw)")
table.insert(lines, insert_at + 3, '  logging.debug("refreshing " .. raw)')
table.insert(lines, insert_at + 4, "  return M.create_session(store.get(raw))")
table.insert(lines, insert_at + 5, "end")
vim.fn.writefile(lines, auth)

-- open the glass so the re-check has somewhere to render, then fire the
-- save-triggered re-check the cascade registered
require("scry.glass").open(work)
H.ok(H.wait(function()
  return require("scry.glass")._state.report ~= nil
end, 8000), "glass checked")

local warned = {}
local rn = vim.notify
vim.notify = function(msg, level)
  if level == vim.log.levels.WARN then
    warned[#warned + 1] = msg
  end
end
cascade._recheck("on save")
H.ok(H.wait(function()
  return #warned > 0
end, 8000), "re-check produced a warning")
vim.notify = rn

local joined = table.concat(warned, "\n")
H.ok(joined:find("VIOLATED", 1, true) ~= nil, "the withheld prohibition caught the conjured code")
H.ok(joined:find("logging", 1, true) ~= nil, "the violated pattern is named")
H.ok(joined:find("lua/auth.lua:", 1, true) ~= nil, "with evidence: file and line")

-- 6) the settle path: the seeding claim flips absent → defined on disk
H.ok(H.wait(function()
  local glass = require("scry.glass")
  local v = glass._state.report and glass._state.report.verdicts[map.claim_id(absent)]
  return v and v.status == "backed"
end, 8000), "the claim that seeded the work is now backed (∅ unratified until ratified)")

cascade.stop()
H.done("cascade_spec PASS")
