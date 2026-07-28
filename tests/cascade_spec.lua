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
local FEATURE = absent.feature

-- 1) build() is pure and shaped right
local built = cascade.build(absent, "define refresh_token using the session store")
H.eq(built.file, "lua/auth.lua", "target file extracted")
H.eq(built.symbol, "refresh_token", "target symbol extracted")
H.eq(#built.items, 1, "one seeded entry")
H.eq(built.items[1].user_data.scry.feature, "a session can be refreshed", "entry carries scry's own user_data")
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

-- 4) cascade accepts contains and exercises; nothing else
local never_claim = hold.claims[1]
H.eq(pcall(cascade.build, never_claim, "x"), false, "cascade refuses a never claim")

-- 4a) an exercises claim cascades into a CHECK. The entry text asks for a
-- spec and carries the assertion — nothing about how to implement anything.
local ex = { kind = "exercises", target = "tests/auth_spec.lua:refresh reissues a session", feature = "a session can be refreshed" }
local ex_built = cascade.build(ex, "write a spec asserting refresh reissues a session")
H.eq(ex_built.kind, "exercises", "the build knows which rung it is on")
H.eq(ex_built.file, "tests/auth_spec.lua", "the spec path is the target file")
H.eq(ex_built.symbol, "refresh reissues a session", "the assertion label survives")
H.ok(ex_built.items[1].text:find("needs a spec", 1, true) ~= nil, "asks for a check: " .. ex_built.items[1].text)
H.eq(
  cascade.build({ kind = "exercises", target = "tests/x_spec.lua", feature = "a session can be refreshed" }, "i").file,
  "tests/x_spec.lua",
  "a claim naming only a file still builds"
)

-- 4b) the tripwire is SCOPED to the feature being cascaded. A different
-- feature's prohibition is never checked against this code (nevers run over
-- their own feature's footprint), so treating it as a leak would block honest
-- work — a word one feature forbids is often another's whole vocabulary.
vim.fn.writefile({
  "feature " .. FEATURE,
  "  never",
  "    logging\\.debug",
  "",
  "feature billing",
  "  never",
  "    token", -- 'token' is this feature's vocabulary, billing's prohibition
}, work .. "/holdout.scry")
H.eq(
  pcall(cascade.seed, work, absent, "define refresh_token from the stored token", false),
  true,
  "a foreign feature's prohibition does not block this cascade"
)
-- ...while this feature's own prohibition still does
vim.fn.writefile({ "feature " .. FEATURE, "  never", "    refresh_token" }, work .. "/holdout.scry")
H.eq(
  pcall(cascade.seed, work, absent, "define refresh_token", false),
  false,
  "the feature's own prohibition still trips the tripwire"
)
-- restore the fixture holdout for the rest of the spec
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/holdout.scry"), work .. "/holdout.scry")

-- 4c) INDEPENDENCE OF THE CHECK. When conjuring code, the feature's spec
-- paths are withheld too. A code request that names the test is a request to
-- satisfy the test — which is the one thing an acceptance check must not be
-- written to do, and the reason a conjured test is worth anything at all.
local mapf = work .. "/.scry/map.scry"
local base = vim.fn.readfile(mapf)
vim.fn.writefile(vim.list_extend(vim.deepcopy(base), { "  exercises", "    tests/auth_spec.lua" }), mapf)
H.eq(
  pcall(cascade.seed, work, absent, "make tests/auth_spec.lua pass", false),
  false,
  "an intent naming the feature's spec trips the tripwire"
)
H.eq(
  pcall(cascade.seed, work, absent, "define refresh_token from the stored session", false),
  true,
  "an intent that describes the behaviour instead passes"
)
-- ...but conjuring the SPEC may of course name the spec
H.eq(
  pcall(cascade.seed, work, {
    kind = "exercises",
    target = "tests/auth_spec.lua",
    feature = "a session can be refreshed",
  }, "write a spec for tests/auth_spec.lua", false),
  true,
  "the spec's own cascade is not blocked by its own path"
)
H.ok(vim.loop.fs_stat(work .. "/tests/auth_spec.lua") ~= nil, "seeding created the absent spec file")
vim.fn.writefile(base, mapf)

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
-- Fire the REAL wire: write the buffer and let the cascade's autocmd run.
-- (Calling _recheck() directly would test the check and skip the trigger —
-- which is exactly how a broken autocmd pattern once passed the specs.)
local sbuf = vim.fn.bufadd(auth)
vim.fn.bufload(sbuf)
vim.api.nvim_buf_call(sbuf, function()
  vim.cmd("silent edit!") -- pick up the on-disk edit above
  vim.cmd("silent write")
end)
H.ok(H.wait(function()
  return #warned > 0
end, 8000), "saving the seeded file fired the cascade's re-check")
vim.notify = rn

local joined = table.concat(warned, "\n")
H.ok(joined:find("VIOLATED", 1, true) ~= nil, "the withheld prohibition caught the conjured code")
H.ok(joined:find("logging", 1, true) ~= nil, "the violated pattern is named")
H.ok(joined:find("lua/auth.lua:", 1, true) ~= nil, "with evidence: file and line")

-- 5b) the re-check is SCOPED to the feature's files. The feature's globs live
-- in the map and its prohibitions in the holdout, so checking the holdout
-- alone would leave claims unscoped and report violations in files the
-- feature doesn't own — a false violation costs more trust than a missed one.
local outsider = work .. "/lua/logging.lua" -- outside the feature's footprint
local ol = vim.fn.readfile(outsider)
table.insert(ol, #ol, 'local _unused = "logging.debug appears here too"')
vim.fn.writefile(ol, outsider)
local warned2 = {}
vim.notify = function(msg, level)
  if level == vim.log.levels.WARN then
    warned2[#warned2 + 1] = msg
  end
end
local done2 = false
cascade._recheck("scope test")
H.wait(function()
  done2 = true
  return false
end, 1500)
vim.notify = rn
for _, w in ipairs(warned2) do
  H.ok(w:find("logging.lua", 1, true) == nil, "no violation reported outside the feature's files")
end

-- 6) the settle path: the seeding claim flips absent → defined on disk
H.ok(H.wait(function()
  local glass = require("scry.glass")
  local v = glass._state.report and glass._state.report.verdicts[map.claim_id(absent)]
  return v and v.status == "backed"
end, 8000), "the claim that seeded the work is now backed (∅ unratified until ratified)")

cascade.stop()
H.done("cascade_spec PASS")
