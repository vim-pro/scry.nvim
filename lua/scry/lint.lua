-- How a feature is WRITTEN, as against whether it is true.
--
-- Every other check in scry asks the code a question. This one asks nothing
-- of the code at all — it reads the names in the map and reports the ones
-- whose shape makes a map hard to read. A lint finding is never a verdict:
-- the map is a document someone wrote, and how it is worded is theirs.
--
-- THE RULES COME FROM THE QUALITY USER STORY FRAMEWORK (Lucassen, Dalpiaz,
-- van der Werf and Brinkkemper, Requirements Engineering 21(3)), which
-- defines thirteen criteria and validates them against 1023 user stories
-- from eighteen companies. Only some of the thirteen are implemented here,
-- and the omissions are the point.
--
-- Their tool draws the line the same way: it implements the criteria a
-- program can decide — well-formed, atomic, minimal, uniform, unique — and
-- deliberately excludes the semantic ones, because deciding whether a name
-- states the problem rather than the solution takes understanding rather
-- than parsing. Scry keeps that line. `problem-oriented` and `conceptually
-- sound` are real criteria and are not checked here; a linter that guesses
-- at meaning would be wrong often enough to teach you to ignore it.
--
-- The other half of their design is a bias toward recall: a finding is
-- worth raising even when it might be nothing, because a missed defect
-- costs more than a glance at a false one. So these flag rather than
-- assert, and every message says what the reader might do rather than what
-- is wrong.
local M = {}

-- Openers that are not an active-verb goal. Cockburn's rule for naming a
-- use case is an active-verb goal phrase for the primary actor's goal —
-- and a map at sea level reads best when every line starts with the verb,
-- because the first word is the one that gets read (NN/g's eyetracking on
-- scanning: people scan rather than read, and front-loaded text is what
-- survives the scan).
--
-- A closed list, not a part-of-speech test. There is no tagger here, and a
-- wrong guess about English would be worse than a short honest list.
local NOT_A_VERB = {
  be = true,
  being = true,
  ["the"] = true,
  a = true,
  an = true,
  all = true,
  any = true,
  how = true,
  what = true,
  when = true,
  where = true,
  why = true,
  users = true,
  user = true,
  people = true,
  someone = true,
  everyone = true,
  it = true,
  there = true,
  this = true,
}

-- A name this long has usually stopped being a name.
local LONG_WORDS = 12

-- Two names this alike are worth looking at together.
local ALIKE = 0.6

---@param name string
---@return string[]
local function words(name)
  local out = {}
  for w in name:lower():gmatch("[%a']+") do
    out[#out + 1] = w
  end
  return out
end

-- Words too common to say two names are about the same thing.
local NOISE = {
  a = true,
  an = true,
  the = true,
  to = true,
  of = true,
  in_ = true,
  ["in"] = true,
  on = true,
  at = true,
  for_ = true,
  ["for"] = true,
  and_ = true,
  ["and"] = true,
  or_ = true,
  ["or"] = true,
  your = true,
  you = true,
  it = true,
  its = true,
  that = true,
  this = true,
  with = true,
  from = true,
  as = true,
  is = true,
  be = true,
}

---@param name string
---@return table<string, true>
local function meaningful(name)
  local set = {}
  for _, w in ipairs(words(name)) do
    if not NOISE[w] and #w > 2 then
      set[w] = true
    end
  end
  return set
end

--- How much two names have in common, 0 to 1 (Jaccard over content words).
---@param a table<string, true>
---@param b table<string, true>
---@return number
function M.overlap(a, b)
  local shared, total = 0, 0
  local seen = {}
  for w in pairs(a) do
    seen[w] = true
    total = total + 1
    if b[w] then
      shared = shared + 1
    end
  end
  for w in pairs(b) do
    if not seen[w] then
      total = total + 1
    end
  end
  if total == 0 then
    return 0
  end
  return shared / total
end

--- Where a name joins two goals.
---
--- ATOMIC, the criterion a drafted map breaks hardest: a feature expresses
--- exactly one thing a person can do. `and` and `or` in a name are usually
--- two features wearing one row, and a row that is two things is a row
--- nobody can finish, ratify, or scan.
---
--- Not every conjunction joins two goals — "terms and conditions" is one
--- noun — so this reports rather than concludes, and says so.
---@param name string
---@return string? the conjunction found
function M.conjunction(name)
  for _, w in ipairs({ "and", "or" }) do
    if name:lower():find("%s" .. w .. "%s") then
      return w
    end
  end
  return nil
end

--- Read a map's feature names and report what a reader might want to change.
---
--- Findings only, in map order, each with the line it is about. Nothing is
--- rewritten and nothing is a verdict.
---@param map_ scry.Map
---@return { lnum: integer, feature: string, rule: string, text: string }[]
function M.findings(map_)
  local out = {}
  local prepared = {}

  for _, f in ipairs(map_.features) do
    local name = f.name
    prepared[#prepared + 1] = { feature = f, set = meaningful(name) }

    local conj = M.conjunction(name)
    if conj then
      out[#out + 1] = {
        lnum = f.lnum,
        feature = name,
        rule = "atomic",
        text = ("joins two goals with `%s` — if both halves are things a person does, they are two features"):format(
          conj
        ),
      }
    end

    local first = (words(name))[1]
    if first and NOT_A_VERB[first] then
      out[#out + 1] = {
        lnum = f.lnum,
        feature = name,
        rule = "uniform",
        text = ("starts with `%s` rather than a verb — a name is what someone DOES, and the first word is the one that gets read"):format(
          first
        ),
      }
    end

    local n = #words(name)
    if n > LONG_WORDS then
      out[#out + 1] = {
        lnum = f.lnum,
        feature = name,
        rule = "minimal",
        text = ("%d words — long enough that the detail may belong in the prose beneath it"):format(n),
      }
    end
  end

  -- UNIQUE, pairwise. Exact repeats cannot appear — naming a feature twice
  -- re-opens it (see |scry-reopening|) — so what is left is the harder kind:
  -- two names that mean the same thing. Their taxonomy calls the useful case
  -- `different means, same end`, and it is the one worth a reader's eye:
  -- usually the two should be one feature with both sets of members.
  for i = 1, #prepared do
    for j = i + 1, #prepared do
      local score = M.overlap(prepared[i].set, prepared[j].set)
      if score >= ALIKE then
        out[#out + 1] = {
          lnum = prepared[j].feature.lnum,
          feature = prepared[j].feature.name,
          rule = "unique",
          text = ("reads like `%s` (line %d) — if they are one capability, make them one feature"):format(
            prepared[i].feature.name,
            prepared[i].feature.lnum
          ),
        }
      end
    end
  end

  table.sort(out, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.rule < b.rule
  end)
  return out
end

--- Put the findings in the quickfix list, where work goes.
function M.to_quickfix()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local found = M.findings(map_)
  if #found == 0 then
    vim.notify(("[scry] %d feature name(s), nothing to flag"):format(#map_.features))
    return
  end

  local items = {}
  for _, f in ipairs(found) do
    items[#items + 1] = {
      bufnr = state.buf,
      lnum = f.lnum,
      col = 1,
      text = ("%s: %s"):format(f.rule, f.text),
      type = "W",
      user_data = { scry = { lint = f.rule } },
    }
  end
  vim.fn.setqflist({}, " ", { title = "scry: how the map is written", items = items })
  vim.cmd("copen")
  vim.notify(
    ("[scry] %d suggestion(s) over %d feature(s) — none of them is a verdict; the wording is yours"):format(
      #found,
      #map_.features
    )
  )
end

return M
