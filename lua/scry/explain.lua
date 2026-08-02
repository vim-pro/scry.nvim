-- What the buffer is telling you, in plain language.
--
-- `g?` in the glass turns on a gloss beside every line: what each row IS,
-- what its verdict actually asserts, and — the part that matters most — what
-- that verdict does NOT assert. Press it again and it goes.
--
-- THIS IS NOT THE STARTER BLOCK COMING BACK. That was tutorial text living
-- IN the map: prose, so nothing objected to it, and it was saved into
-- `.scry/map.scry` and re-read by every drafting pass. Instructions inside
-- the document they are teaching you to write have no way out of it.
--
-- These are virtual lines. They cannot be saved, cannot be edited, cannot be
-- sent to a model, and are off by default. And they are not generic: every
-- sentence here is about the row it is under and the verdict that row
-- actually got.
--
-- THE WORDING IS LOAD-BEARING, exactly as the verdict labels are. Nothing
-- here may claim more than the engine claimed — see |scry-honesty|, which
-- these sentences are the reader-facing half of. `✓ present (file)` means a
-- file is on disk and nothing more, and saying so is the whole point.
local M = {}

-- What each claim verdict asserts, and what it does not.
--
-- Keyed by the STATUS the engine returned rather than by its label, so a
-- reworded label cannot silently detach its explanation from its verdict.
local CLAIM = {
  backed = "this holds right now, against the files on disk",
  clean = "nothing in this feature's files matches that pattern — evidence, not proof",
  missing = "not there. that is work you have described and not done yet",
  violated = "PROOF. the thing you forbade is in your code, at the line below",
  unchecked = "nothing here could answer this. it is not a pass",
}

-- The rungs, which are the honest part. `backed` covers all of these and they
-- are not the same claim: the label says which one you got.
local RUNG = {
  ["present (file)"] = "the file is on disk. nothing has looked inside it",
  ["defined"] = "a definition by that name exists in that file. nothing about what it does",
  ["defined (text)"] = "a LINE there looks like a definition of it — no grammar for this language here, so it could be inside a comment",
  ["referenced (text)"] = "that name appears in this feature's files. not a proven call",
  ["no matches (rg)"] = "no text matches it. a clean prohibition is evidence, not proof",
}

-- What a feature's rolled-up state means for you.
local FEATURE = {
  done = "every claim holds AND something was run to prove it. the only state that means `works`",
  in_place = "every claim holds and NOTHING RAN. the structure is there; whether it works is unproven",
  broken = "something that used to hold does not. the most urgent row on the page",
  partial = "some of it holds. the rest is the work",
  absent = "nothing holds yet. a capability you have described and not built — this is on purpose",
  unknown = "nothing has answered for this yet. NOT progress",
  unevidenced = "named, with nothing under it to check. press + to find the files it is made of",
}

--- The gloss for a feature's line.
---@param verdict table?
---@return string?
function M.feature(verdict)
  return verdict and FEATURE[verdict.state] or nil
end

--- The gloss for a member's line.
---
--- Two sentences at most: what the verdict asserts, and which rung of
--- evidence it is. A reader who learns only one thing from this mode should
--- learn that those are different questions.
---@param verdict table? the claim verdict from the report
---@return string?
function M.member(verdict)
  if not verdict then
    return "no verdict yet — the check has not settled, or nothing can answer this kind"
  end
  local parts = {}
  local rung = verdict.label and verdict.label:match("^%S+%s+(.*)$")
  if rung and RUNG[rung] then
    parts[#parts + 1] = RUNG[rung]
  elseif CLAIM[verdict.status] then
    parts[#parts + 1] = CLAIM[verdict.status]
  end
  if verdict.status == "violated" then
    parts = { CLAIM.violated }
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

--- The gloss for a feature's description.
function M.description()
  return "prose. never checked, never marked — this is what you believe the capability is for"
end

--- The gloss for the counts in the header.
---
--- THE CEILING LIVES HERE TOO. Scry says the one thing that would most
--- improve its answers once per project, as a notification — and a
--- notification is gone the moment anything else prints. Someone who read it,
--- blinked, and wondered what it said had nowhere to look. This is that
--- somewhere.
---@param debt table?
---@param limit table? the advice item, from scry.advice.best
---@return string?
function M.header(debt, limit)
  if not debt then
    return nil
  end
  if limit then
    return ("%s · %s"):format(limit.say, limit.how)
  end
  return ("%d feature%s described here · %d file%s in this project no feature claims · everything below is computed, never stored"):format(
    debt.features,
    debt.features == 1 and "" or "s",
    debt.unclaimed or 0,
    (debt.unclaimed or 0) == 1 and "" or "s"
  )
end

-- On or off, per session. Not per project: it is a reading mode, and which
-- project you are looking at has nothing to do with whether you want it.
local showing = false

---@return boolean
function M.showing()
  return showing
end

--- Turn the gloss on or off and redraw.
function M.toggle()
  showing = not showing
  local glass = require("scry.glass")
  glass.render()
  vim.notify(showing and "[scry] explaining · g? to stop" or "[scry] g? to explain again")
end

return M
