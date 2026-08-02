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


-- UNREAD outranks DONE. Every claim can hold while nobody has read a word of
-- the feature — which is exactly what a drafting pass produces, and what a
-- freshly cloned map looks like, since the trail is per-machine and does not
-- travel with the file. Reporting that as `✓ done` puts a finished product on
-- the one line the whole design says you scan.
local unread_root = vim.fn.tempname()
vim.fn.mkdir(unread_root, "p")
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

-- with no root there is no engagement axis to read, so the evidence axis
-- answers alone — honest about what it could see
H.eq(feat.verdict(drafted.features[1], all_backed).state, "done", "no root: the evidence axis alone")

local v = feat.verdict(drafted.features[1], all_backed, unread_root)
H.eq(v.state, "unread", "with a root and no trail: unread, not done")
H.eq(v.backed, 2, "the evidence is still reported")
-- Same shape as every other state, so the closed map reads as one column:
-- `– unread 2 of 2` beside `◐ 2 of 4`, where `(2 of 2 backed)` was half
-- again as long and broke the rhythm of the one view built for scanning.
H.ok(v.label:find("unread 2 of 2", 1, true) ~= nil, "and the label says so: " .. v.label)
H.eq(feat.tally(drafted, all_backed, unread_root).unread, 1, "the header counts it apart from done")
H.eq(feat.tally(drafted, all_backed, unread_root).done, 0, "and not as done")

-- ONE owned claim is enough. The question is whether a human has been through
-- this at all, not whether they finished; holding out for every claim would
-- report `unread` for work visibly in progress.
require("scry.provenance").record(unread_root, drafted.claims[1], "authored")
H.eq(feat.engaged(unread_root, drafted.features[1]), true, "one edited claim means the feature was read")
H.eq(feat.verdict(drafted.features[1], all_backed, unread_root).state, "done", "so it reads done")

-- Narrow on purpose: unread displaces `done` only. A half-backed feature
-- nobody has touched still reads as progress, because that is the more useful
-- reading and it is not claiming to be finished.
local half = map.parse({ "feature f", "  contains", "    a.lua:one", "    b.lua:two" })
local one = { at = os.time(), verdicts = {} }
one.verdicts[map.claim_id(half.claims[1])] = { status = "backed", fidelity = "ts-def", label = "✓ defined" }
one.verdicts[map.claim_id(half.claims[2])] = { status = "missing", fidelity = "ts-def", label = "✗ absent" }
local fresh_root = vim.fn.tempname()
vim.fn.mkdir(fresh_root, "p")
H.eq(feat.verdict(half.features[1], one, fresh_root).state, "partial", "half-backed and untouched is still partial")

H.done("feature_spec PASS")
