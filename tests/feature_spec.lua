-- Features: the sea-level layer, its derived footprint, and the rollup.
--
-- The altitude rule this file pins down: a claim is EVIDENCE for a feature,
-- never a peer of one. So a feature's state is derived — you cannot author
-- it — and its scope is derived too, from the files its own claims name.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local map = require("scry.map")
local feat = require("scry.feature")
local debt = require("scry.debt")

local SRC = {
  "feature a user can reset their password",
  "  Requests a link by email. The link burns on use.",
  "",
  "  contains",
  "    lua/auth/reset.lua:request_reset",
  "    lua/auth/reset.lua:consume_link",
  "  calls",
  "    mailer::send",
  "  never",
  "    token.*log",
  "  exercises",
  "    tests/reset_spec.lua:the link burns on use",
  "",
  "feature an admin can revoke a session",
  "  Not built yet.",
  "",
  "  contains",
  "    lua/auth/admin.lua:revoke",
  "",
  "feature sessions expire",
  "  Named, with nothing checkable under it yet.",
}
local m = map.parse(SRC)

-- 1) the grammar: features are top level, claims are their evidence
H.eq(#m.features, 3, "three features parsed")
H.eq(m.features[1].name, "a user can reset their password", "the sea-level statement is the name, verbatim")
H.eq(#m.features[1].claims, 5, "five claims are evidence for the first feature")
H.eq(#m.features[3].claims, 0, "a feature may be named with no evidence")
H.eq(m.claims[1].feature, "a user can reset their password", "a claim knows which feature it backs")
H.eq(#m.claims, 6, "claims across the whole map")

-- prose is still prose; a sentence between features is never a claim
H.ok(m.features[1].claims[1].target == "lua/auth/reset.lua:request_reset", "first claim is the first indented target")

-- 2) FOOTPRINT IS DERIVED. A glob is a directory and a feature is not one —
-- it is a picked set of elements scattered across files. Deriving the scope
-- from the claims means it cannot drift from what it is meant to describe.
local fp = map.footprint(m.features[1])
H.eq(#fp, 2, "footprint is the files the located claims name, deduplicated")
H.eq(fp[1], "lua/auth/reset.lua", "contains contributes its path — twice over, counted once")
H.eq(fp[2], "tests/reset_spec.lua", "exercises contributes its spec, label stripped")
H.ok(not vim.tbl_contains(fp, "mailer"), "calls carries a hint, not a path — it contributes nothing")

-- a feature that locates nothing has an empty footprint, and that is
-- meaningful: an unscoped prohibition has nowhere to look
H.eq(#map.footprint(m.features[3]), 0, "a feature with no located claims has no footprint")

-- 3) THE ROLLUP. Nothing here is authored; a feature's state is whatever its
-- evidence currently says.
local function report_of(pairs_)
  local verdicts = {}
  for target, status in pairs(pairs_) do
    for _, c in ipairs(m.claims) do
      if c.target == target then
        verdicts[map.claim_id(c)] = { status = status, fidelity = "ts-def", label = status }
      end
    end
  end
  return { at = os.time(), verdicts = verdicts }
end

local all_backed = report_of({
  ["lua/auth/reset.lua:request_reset"] = "backed",
  ["lua/auth/reset.lua:consume_link"] = "backed",
  ["mailer::send"] = "backed",
  ["token.*log"] = "clean",
  ["tests/reset_spec.lua:the link burns on use"] = "backed",
})
local v = feat.verdict(m.features[1], all_backed)
H.eq(v.state, "done", "every claim holding makes the feature done")
H.eq(v.label, "✓ done", "and says so plainly")

-- a clean prohibition counts as holding — it is evidence, and the rollup
-- must not treat "nothing matched" as an unanswered question
H.eq(v.backed, 5, "clean counts alongside backed")

-- one violation outranks four passes: a regression is the most urgent line
local one_broken = report_of({
  ["lua/auth/reset.lua:request_reset"] = "backed",
  ["lua/auth/reset.lua:consume_link"] = "backed",
  ["mailer::send"] = "backed",
  ["token.*log"] = "violated",
  ["tests/reset_spec.lua:the link burns on use"] = "backed",
})
local vb = feat.verdict(m.features[1], one_broken)
H.eq(vb.state, "broken", "a violation makes the feature broken, however much else holds")
H.ok(vb.label:find("1 of 5", 1, true) ~= nil, "and counts what broke: " .. vb.label)

-- partial work is in flight and reads as such
local half = report_of({
  ["lua/auth/reset.lua:request_reset"] = "backed",
  ["lua/auth/reset.lua:consume_link"] = "missing",
  ["mailer::send"] = "missing",
  ["token.*log"] = "clean",
  ["tests/reset_spec.lua:the link burns on use"] = "missing",
})
local vp = feat.verdict(m.features[1], half)
H.eq(vp.state, "partial", "some evidence holding is partial")
H.ok(vp.label:find("2 of 5", 1, true) ~= nil, "showing how far along: " .. vp.label)

-- nothing holding yet is the state you create ON PURPOSE — it is the work,
-- not a fault, and it must be distinguishable from a regression
local vn = feat.verdict(m.features[2], report_of({ ["lua/auth/admin.lua:revoke"] = "missing" }))
H.eq(vn.state, "absent", "no evidence holding is not-yet")
H.eq(vn.label, "✗ not yet", "worded as work, not as failure")

-- and a feature with no claims is neither done nor broken
local vu = feat.verdict(m.features[3], all_backed)
H.eq(vu.state, "unevidenced", "prose with nothing checkable under it")
H.ok(vu.label:find("no evidence", 1, true) ~= nil, "named honestly: " .. vu.label)

-- with no report at all, nothing is done
H.eq(
  feat.verdict(m.features[1], nil).state,
  "unknown",
  "before any check, a feature is unknown — never partial, which would claim progress"
)

-- 4) THE HEADER LEADS WITH FEATURES. The reader's question is what the
-- product does, not how many subfunctions resolved; claim numbers are the
-- evidence behind that and come second.
local d = debt.count(m, one_broken)
H.eq(d.features, 3, "features counted")
H.eq(d.broken, 1, "the broken one")
H.eq(d.todo, 1, "unevidenced reads as work to do")
H.eq(d.unknown, 1, "the feature nothing answered for is unknown, not partial")
local header = debt.header(d, one_broken.at)
local first_line = vim.split(header, "\n", { plain = true })[1]
H.ok(first_line:find("3 features", 1, true) ~= nil, "features lead line one: " .. first_line)
H.ok(first_line:find("claims", 1, true) == nil, "claim counts are NOT on the first line")
H.ok(header:find("6 claims", 1, true) ~= nil, "they are on the second, as evidence")

-- 5) tally covers every feature exactly once
local counts, total = feat.tally(m, one_broken)
H.eq(total, 3, "tally sees every feature")
H.eq(
  counts.broken + counts.done + counts.partial + counts.unknown + counts.absent + counts.unevidenced,
  3,
  "each counted once"
)


-- THERE IS ONE AXIS HERE, AND IT IS EVIDENCE.
--
-- There used to be a second. `unread` meant every claim held and nobody had
-- recorded reading the description — a whole subsystem of per-machine trails,
-- an ∅ marker on every row, and a word on the line you scan, none of which
-- said anything about the code. `– unread 4 of 4` on a feature whose four
-- members each already showed their own verdict taught a reader nothing they
-- could act on. It was the last of the ratification design.
--
-- What is left says only what the evidence says: every claim holding is
-- `done`, whoever wrote it and whether or not anyone has been through it.
local drafted = map.parse({
  "feature you can sign in",
  "  contains",
  "    lua/auth.lua:sign_in",
  "    lua/store.lua:session_put",
})
local all_backed = { at = os.time(), verdicts = {} }
for _, c in ipairs(drafted.claims) do
  all_backed.verdicts[map.claim_id(c)] = { status = "backed", fidelity = "ts-def", label = "✓ defined" }
end
H.eq(feat.verdict(drafted.features[1], all_backed).state, "done", "every claim holding is done")
-- A root used to switch on the engagement axis. It is accepted and ignored,
-- so no caller has to change shape and none of them can reintroduce it.
local anywhere = vim.fn.tempname()
vim.fn.mkdir(anywhere, "p")
H.eq(feat.verdict(drafted.features[1], all_backed, anywhere).state, "done", "and a root changes nothing")
H.eq(feat.tally(drafted, all_backed, anywhere).done, 1, "the header counts it as done")
H.eq(feat.tally(drafted, all_backed, anywhere).unread, nil, "and has no count for a state that is gone")
H.eq(feat.engaged, nil, "the engagement test is gone, not merely unused")

-- A half-backed feature reads as progress, which is the more useful reading
-- and is not a claim of completion.
local half = map.parse({ "feature f", "  contains", "    a.lua:one", "    b.lua:two" })
local one = { at = os.time(), verdicts = {} }
one.verdicts[map.claim_id(half.claims[1])] = { status = "backed", fidelity = "ts-def", label = "✓ defined" }
one.verdicts[map.claim_id(half.claims[2])] = { status = "missing", fidelity = "ts-def", label = "✗ absent" }
local fresh_root = vim.fn.tempname()
vim.fn.mkdir(fresh_root, "p")
H.eq(feat.verdict(half.features[1], one, fresh_root).state, "partial", "half-backed and untouched is still partial")

H.done("feature_spec PASS")
