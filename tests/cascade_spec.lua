-- The thesis test. An absent claim becomes quickfix work, the conjurer casts
-- it, and the prohibition — told to the generator up front AND re-checked
-- after — catches a violating result.
--
-- Two load-bearing walks: the feature's own prohibitions RIDE ALONG in the
-- outgoing intent (prevention), and the feature's spec paths do NOT
-- (independence of the check). Neither is hoped for here; both are checked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local cascade = require("scry.cascade")

-- A workspace copy of the fixture, so casts can really edit files.
local work = vim.fn.tempname()
vim.fn.mkdir(work .. "/lua", "p")
vim.fn.mkdir(work .. "/.scry", "p")
for _, f in ipairs({ "auth.lua", "store.lua", "logging.lua" }) do
  vim.fn.writefile(vim.fn.readfile(H.fixture .. "/lua/" .. f), work .. "/lua/" .. f)
end
vim.fn.writefile(vim.fn.readfile(H.fixture .. "/map.scry"), work .. "/.scry/map.scry")
require("scry").setup({})

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

-- 2) PROHIBITIONS RIDE ALONG: seeding puts this feature's never-patterns in
-- the outgoing intent, so the generator is told the rules it will be checked
-- against. Prevention and detection, not one or the other.
local seeded = cascade.seed(work, absent, "define refresh_token using the session store", false)
H.ok(seeded.intent:find("logging\\.debug", 1, true) ~= nil, "the feature's prohibition rides in the intent")
H.ok(seeded.intent:find("io\\.write", 1, true) ~= nil, "all of them do")
H.ok(seeded.intent:find("must never", 1, true) ~= nil, "stated as a rule, not decoration")

-- 4) cascade accepts contains and exercises; nothing else
local never_claim
for _, c in ipairs(m.claims) do
  if c.kind == "never" then
    never_claim = c
    break
  end
end
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

-- 4b) the riding rules are SCOPED to the feature being cascaded. A different
-- feature's prohibition is never checked against this code (nevers run over
-- their own feature's footprint), so it has no business in the request — a
-- word one feature forbids is often another's whole vocabulary.
local mapf0 = work .. "/.scry/map.scry"
local base0 = vim.fn.readfile(mapf0)
vim.fn.writefile(
  vim.list_extend(vim.deepcopy(base0), { "", "feature billing", "  never", "    secret_key" }),
  mapf0
)
local scoped = cascade.seed(work, absent, "define refresh_token from the stored token", false)
H.ok(scoped.intent:find("logging\\.debug", 1, true) ~= nil, "this feature's rule rides")
H.eq(scoped.intent:find("secret_key", 1, true), nil, "billing's rule does not")
vim.fn.writefile(base0, mapf0)

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
  "an intent that describes the behavior instead passes"
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
-- VIOLATING implementation and saving: a rule it was told, broken anyway,
-- is still caught — telling does not replace checking.
cascade.seed(work, absent, "define refresh_token", false)
local items = vim.fn.getqflist({ items = 1 }).items
H.eq(#items, 1, "list seeded")
H.ok(items[1].text:find("refresh_token", 1, true) ~= nil, "entry text names the symbol")

-- the "conjured" result: correct-looking, and it logs a token anyway
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
H.ok(joined:find("VIOLATED", 1, true) ~= nil, "the prohibition caught the conjured code")
H.ok(joined:find("logging", 1, true) ~= nil, "the violated pattern is named")
H.ok(joined:find("lua/auth.lua:", 1, true) ~= nil, "with evidence: file and line")

-- 5b) the re-check is SCOPED to the feature's files. An unscoped check would
-- search the whole project and report violations in files the feature does
-- not own — a false violation costs more trust than a missed one.
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
end, 8000), "the claim that seeded the work is now backed")

cascade.stop()
H.done("cascade_spec PASS")
