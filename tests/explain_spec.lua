-- `g?` — what the buffer is telling you, in plain language.
--
-- The glass is deliberately quiet. Verdicts appear where they discriminate
-- and stay away where they do not, a healthy verdict shared by every member
-- of a feature is printed on none of them, and column one says nothing when a
-- feature is fine. That is right for READING and wrong for LEARNING: the
-- first time you meet a silent row, silence and "nothing ran" look identical.
--
-- This mode says what was withheld, and what each verdict does and does not
-- assert. It is the reader-facing half of |scry-honesty|.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/helpers.lua")

local explain = require("scry.explain")

-- 1) THE RUNGS ARE THE POINT. `backed` covers all of these and they are not
-- the same claim — the whole honesty argument is that a green tick means
-- something different depending on which engine produced it.
local file = explain.member({ status = "backed", label = "✓ present (file)" })
H.ok(file:find("on disk", 1, true) ~= nil, "a file-existence verdict says the file is there")
H.ok(file:find("nothing has looked inside", 1, true) ~= nil, "and says that is ALL it says")

local defined = explain.member({ status = "backed", label = "✓ defined" })
H.ok(defined:find("definition", 1, true) ~= nil, "a definition verdict says a definition exists")
H.ok(defined:find("nothing about what it does", 1, true) ~= nil, "and disclaims the body")
H.ok(defined ~= file, "the two greens do not read the same, because they do not mean the same")

-- THE ASYMMETRY, which is the honesty ledger's central claim: a violated
-- prohibition is PROOF, a clean one is only evidence.
local clean = explain.member({ status = "clean", label = "✓ no matches (rg)" })
H.ok(clean:find("evidence, not proof", 1, true) ~= nil, "a clean prohibition is evidence")
local bad = explain.member({ status = "violated", label = "✗ VIOLATED" })
H.ok(bad:find("PROOF", 1, true) ~= nil, "a violated one is proof")

-- `unchecked` IS NOT A PASS, and this is the sentence that has to say so.
local none = explain.member({ status = "unchecked", label = "– unchecked (no engine)" })
H.ok(none:find("not a pass", 1, true) ~= nil, "nothing answering is never a pass")
H.ok(explain.member(nil):find("no verdict yet", 1, true) ~= nil, "and no verdict at all says so plainly")

-- 2) FEATURE STATES, in the reader's terms rather than the engine's.
H.ok(explain.feature({ state = "absent" }):find("on purpose", 1, true) ~= nil, "`not yet` is a state you create")
H.ok(explain.feature({ state = "unknown" }):find("NOT progress", 1, true) ~= nil, "unchecked is not partial")
H.ok(explain.feature({ state = "unevidenced" }):find("+", 1, true) ~= nil, "a bare name points at the way out")
H.eq(explain.feature(nil), nil, "and nothing is explained about a feature with no verdict")

-- 3) A state explain does not know renders no sentence rather than a wrong
-- one.
H.eq(explain.feature({ state = "no-such-state" }), nil, "an unknown state explains nothing")

-- 4) IT IS OFF UNTIL ASKED FOR, and it is a reading mode rather than
-- something about a project — which project you are looking at has nothing to
-- do with whether you want it.
H.eq(explain.showing(), false, "the gloss starts off")

-- 5) NOTHING HERE MAY CLAIM MORE THAN THE ENGINE CLAIMED. These sentences are
-- keyed by the STATUS the engine returned, not by the label's wording, so
-- rephrasing a label cannot silently detach it from its explanation — and a
-- rung it does not recognize falls back to the status rather than inventing a
-- meaning for it.
local unknown_rung = explain.member({ status = "backed", label = "✓ some future engine" })
H.ok(unknown_rung:find("holds right now", 1, true) ~= nil, "an unrecognized rung falls back to the status")
H.eq(unknown_rung:find("inside"), nil, "and does not borrow another rung's disclaimer")

H.done("explain_spec PASS")
