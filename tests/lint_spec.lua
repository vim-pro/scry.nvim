-- How a feature is WRITTEN. Every other spec here asks whether the map is
-- true; this one asks whether it can be read.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local lint = require("scry.lint")
local map = require("scry.map")

local function named(...)
  local lines = {}
  for _, n in ipairs({ ... }) do
    lines[#lines + 1] = "feature " .. n
    lines[#lines + 1] = "  module src/x.lua"
  end
  return map.parse(lines, {})
end

local function rules(found)
  local out = {}
  for _, f in ipairs(found) do
    out[#out + 1] = f.rule
  end
  table.sort(out)
  return table.concat(out, ",")
end

-- 1) ATOMIC — the criterion a drafted map breaks hardest. A feature is
-- exactly one thing a person can do; `and`/`or` in a name is usually two
-- features sharing a row, and a row that is two things cannot be finished,
-- ratified, or scanned. Measured on a real drafting pass: six of eleven.
H.eq(lint.conjunction("Work through a checklist and keep your place"), "and", "an `and` is found")
H.eq(lint.conjunction("Suggest an edit or a whole new checklist"), "or", "and an `or`")
H.eq(lint.conjunction("Tailor a checklist to your own situation"), nil, "a single goal is not flagged")
H.eq(lint.conjunction("Understand a checklist"), nil, "and a word CONTAINING `and` is not a conjunction")

-- The rule reports rather than concludes, and the false positive is
-- deliberate. "Terms and conditions" is one noun; this flags it anyway,
-- because a missed defect costs a reader more than a glance at a wrong
-- one — the recall bias the QUS tool is built around. The message says
-- "if both halves are things a person does", not "this is wrong".
local noun = lint.findings(named("Accept the terms and conditions"))
H.eq(#noun, 1, "a noun-phrase conjunction is flagged too")
H.ok(noun[1].text:find("if both halves", 1, true) ~= nil, "and the wording leaves the call to the reader")

-- 2) UNIFORM — an active-verb goal phrase, which is Cockburn's rule for
-- naming a use case and the shape that makes a list scannable: the first
-- word is the one that gets read.
local passive = lint.findings(named("Be found by a search engine"))
H.eq(rules(passive), "uniform", "a name that does not start with a verb is flagged")
H.eq(#lint.findings(named("Tailor a checklist to your situation")), 0, "a verb-first name is not")
H.eq(#lint.findings(named("Watch along as someone works")), 0, "nor is another")

-- 3) MINIMAL — a name long enough to be prose has stopped being a name.
local long = lint.findings(named("Take a checklist away with you in whatever format your own tools happen to be able to read"))
H.ok(rules(long):find("minimal") ~= nil, "an overlong name is flagged")
H.eq(#lint.findings(named("Browse the library")), 0, "a short one is not")

-- 4) UNIQUE — exact repeats cannot occur, because naming a feature twice
-- re-opens it (see map_spec). What is left is the hard kind: two names for
-- one capability. Their taxonomy calls it `different means, same end`, and
-- it is the failure that took one map to 301 features.
local alike = lint.findings(named(
  "Tailor a checklist to your own situation",
  "Tailor a checklist to your exact situation"
))
H.ok(rules(alike):find("unique") ~= nil, "two names for one thing are flagged")
local pair = nil
for _, f in ipairs(alike) do
  if f.rule == "unique" then
    pair = f
  end
end
H.ok(pair.text:find("line 1", 1, true) ~= nil, "and the finding names the line to compare against")

-- Distinct capabilities that share a noun are NOT duplicates. The whole map
-- is about checklists; flagging every pair that says so would be noise, and
-- noise is how a linter teaches you to ignore it.
H.eq(
  #lint.findings(named(
    "Browse the library",
    "Watch someone work"
  )),
  0,
  "different capabilities are left alone"
)
H.eq(
  rules(lint.findings(named(
    "Tailor a checklist to your situation",
    "Print a checklist onto paper"
  ))):find("unique"),
  nil,
  "and a shared noun alone is not a duplicate"
)

-- Overlap is symmetric and bounded, which is what makes the threshold mean
-- the same thing in both directions.
local a, b = { one = true, two = true }, { two = true, three = true }
H.eq(lint.overlap(a, b), lint.overlap(b, a), "overlap does not depend on order")
H.eq(lint.overlap(a, a), 1, "a name is identical to itself")
H.eq(lint.overlap({}, {}), 0, "and two empty names are not")

-- 5) FINDINGS ARE ORDERED BY THE LINE THEY ARE ABOUT, because they are read
-- in a quickfix list against the buffer they came from.
local many = lint.findings(named(
  "Be found by a crawler",
  "Tailor a checklist",
  "Browse and search the library"
))
local last = 0
for _, f in ipairs(many) do
  H.ok(f.lnum >= last, "findings run down the map, not around it")
  last = f.lnum
end

-- 6) NOTHING IS A VERDICT. A finding carries the line, the name, the rule
-- and a sentence — and no replacement. The map is a document someone wrote;
-- how it is worded is theirs, and a linter that rewrote it would be making
-- a judgment it has no way to earn.
local one = lint.findings(named("Browse and find a checklist"))[1]
H.eq(one.rule, "atomic", "a rule is named")
H.eq(one.feature, "Browse and find a checklist", "with the name it is about")
H.eq(one.lnum, 1, "and the line")
H.eq(one.suggestion, nil, "and no rewrite")
H.eq(one.fix, nil, "under any name")

-- 7) THE SEMANTIC CRITERIA ARE ABSENT ON PURPOSE. `problem-oriented` — a
-- name states the problem, not the solution — is a real criterion and one
-- this map breaks, but deciding it takes understanding rather than parsing.
-- The QUS tool draws the same line for the same reason. A name that encodes
-- its mechanism passes here, and that is honest rather than complete.
H.eq(
  #lint.findings(named("Keep a copy that lives entirely in its link")),
  0,
  "a solution-oriented name is not caught, and nothing pretends otherwise"
)

H.done("lint_spec PASS")
