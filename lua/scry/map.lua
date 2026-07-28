-- The map: plain text in, structure out, plain text back — byte-identical.
--
-- The model keeps the ORIGINAL lines and parses an overlay of references
-- into them (features, sections, claims, each carrying its line number).
-- Serialization returns the lines array, so a parse→serialize round trip
-- cannot lose anything: operations that change the map edit the line in
-- place and re-parse.
--
-- There are no parse errors. A line is a feature header, a section header,
-- a claim (when inside a section), or prose. Prose is preserved verbatim,
-- never checked, never marked.
--
-- ALTITUDE. A feature is a SEA-LEVEL object in Cockburn's sense: one thing
-- a user of this system can accomplish, named the way they would name it.
-- His tests — one person, one place, one sitting; can you go to lunch when
-- it is done; does your standing depend on how many you do — separate it
-- from the two neighbouring altitudes that ruin a map. Above are summaries
-- ("the auth system"), which are groupings, not work. Below are
-- subfunctions ("validate the token"), and those are exactly what claims
-- already are. Cockburn's warning is the one this grammar is built to
-- avoid: a hundred pages of subfunctions "did not serve either its writers
-- or readers", and six user-goal statements replaced them. Claims are
-- therefore SUBORDINATE to a feature, never promoted alongside it.
--
-- FOOTPRINT. A feature's scope is DERIVED — the union of the files its
-- located claims name — never declared. A glob is a directory, and a
-- feature is not a directory; it is a hand-picked set of elements
-- scattered across files (Robillard & Murphy's concern graph). Deriving it
-- also means the scope cannot drift from the claims it is supposed to
-- describe.
--
-- Claim kinds sit on TWO axes, and the split is not cosmetic:
--
--   contains / calls / never   STATIC evidence — a definition node, a text
--     match. Cheap, side-effect-free, computed on every check.
--   exercises                  DYNAMIC evidence — something was run and it
--     passed. Slow, stateful, and it can go stale the instant you edit.
--
-- Structural claims say where things are; an exercised claim says what
-- holds. Most real work needs one of each, which is why neither axis is
-- the primary one.
local M = {}

---@class scry.Stamp
---@field user string  From the "@name" token.
---@field date string  YYYY-MM-DD.
---@field hash string  6 hex chars of sha256(target).

---@class scry.Claim
---@field kind "contains"|"calls"|"never"|"exercises"
---@field target string Trimmed claim text, stamp excluded.
---@field stamp scry.Stamp?
---@field lnum integer 1-based line in the parsed lines array.
---@field feature string Name of the feature this claim is evidence for.

---@class scry.Feature
---@field name string The sea-level statement, verbatim.
---@field lnum integer
---@field claims scry.Claim[]

---@class scry.Map
---@field lines string[] The source of truth; serialize() returns these.
---@field features scry.Feature[]
---@field claims scry.Claim[] All claims across features, in order.

-- A claim line's optional trail suffix. The "  -- @" separator is
-- reserved: a never-pattern needing a literal "-- @user date hex" tail
-- would collide, and the docs say so.
local STAMP_PAT = "^(.-)%s+%-%- (@%S+) (%d%d%d%d%-%d%d%-%d%d) (%x%x%x%x%x%x)%s*$"

---@param lines string[]
---@return scry.Map
function M.parse(lines)
  local map = { lines = lines, features = {}, claims = {} }
  local feature = nil
  local section = nil -- current claim kind, or nil

  for lnum, line in ipairs(lines) do
    local name = line:match("^feature%s+(.+)$")
    if name then
      feature = { name = vim.trim(name), lnum = lnum, claims = {} }
      table.insert(map.features, feature)
      section = nil
    elseif feature then
      local sec = line:match("^  (contains)%s*$")
        or line:match("^  (calls)%s*$")
        or line:match("^  (never)%s*$")
        or line:match("^  (exercises)%s*$")
      if sec then
        section = sec
      elseif section and line:match("^    %S") then
        local body = line:match("^    (.-)%s*$")
        local target, user, date, hash = body:match(STAMP_PAT)
        local claim = {
          kind = section,
          target = target and vim.trim(target) or body,
          stamp = user and { user = user:sub(2), date = date, hash = hash } or nil,
          lnum = lnum,
          feature = feature.name,
        }
        table.insert(feature.claims, claim)
        table.insert(map.claims, claim)
      elseif not line:match("^%s*$") and not line:match("^    ") then
        -- A DEDENTED non-blank line ends the section; the line is prose.
        --
        -- A blank line deliberately does not. It reads like a terminator to a
        -- human, but treating it as one silently demotes every claim after it
        -- to prose — never checked, never rendered, and for a never-block,
        -- routed into the repo by glass.split. Indentation is the grammar;
        -- vertical space is layout.
        section = nil
      end
      -- anything else: prose, preserved in lines, no model entry needed
    end
  end
  return map
end

--- The file a claim names, if it names one. `contains path:symbol` and
--- `exercises path[:label]` locate themselves; `calls` carries a hint, not
--- a path, and `never` is a pattern — neither contributes a location.
---@param claim scry.Claim
---@return string?
function M.claim_path(claim)
  if claim.kind == "contains" then
    return (claim.target:match("^(.-):[%w_.]+$"))
  elseif claim.kind == "exercises" then
    return claim.target:match("^([^:]+):") or claim.target
  end
  return nil
end

--- A feature's footprint: the files its located claims name, in order of
--- first appearance and deduplicated. Empty is meaningful — a feature that
--- locates nothing cannot scope a prohibition, and the resolver says so
--- rather than searching the whole project.
---@param feature scry.Feature
---@return string[]
function M.footprint(feature)
  local out, seen = {}, {}
  for _, claim in ipairs(feature.claims) do
    local path = M.claim_path(claim)
    if path and not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

--- The stored text is the truth; serialization is identity.
---@param map scry.Map
---@return string[]
function M.serialize(map)
  return map.lines
end

--- Parse a file from disk ({} lines if missing).
---@param path string
---@return scry.Map
function M.load(path)
  local f = io.open(path, "r")
  if not f then
    return M.parse({})
  end
  local content = f:read("*a")
  f:close()
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return M.parse(lines)
end

--- Find a feature by name.
---@param map scry.Map
---@param name string
---@return scry.Feature?
function M.feature(map, name)
  for _, f in ipairs(map.features) do
    if f.name == name then
      return f
    end
  end
end

--- Stable identity for a claim (report keys, cross-render matching).
---@param claim scry.Claim
---@return string
function M.claim_id(claim)
  return claim.feature .. "\1" .. claim.kind .. "\1" .. claim.target
end

return M
