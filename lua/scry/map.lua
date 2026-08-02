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
---@field kind string An object kind (`module`, `def`, or one the project
---  declared) or a relation (`never`, `exercises`). See scry.kinds.
---@field target string Trimmed claim text, stamp excluded.
---@field desc string[] The member's OWN intent, indented under it. What a
---  member is for, as distinct from what the feature is for — and the only
---  thing a re-conjure could regenerate a member FROM.
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

--- Parse a map.
---
--- `known` is the set of kinds this project has (scry.kinds.all). It is a
--- parameter rather than a lookup because a kind is project-shaped, and
--- because without it a member cannot be told from prose — see the loop.
--- Omitted, only the builtins and relations are grammar, which is the
--- right default: those are the ones that hold everywhere.
---@param lines string[]
---@param known table<string, any>? kind name -> anything truthy
---@return scry.Map
function M.parse(lines, known)
  local map = { lines = lines, features = {}, claims = {} }
  local kinds = require("scry.kinds")
  if known then
    known = vim.tbl_extend("keep", known, kinds.BUILTIN)
  else
    known = vim.deepcopy(kinds.BUILTIN)
  end
  local feature = nil
  local section = nil -- current legacy section, or nil
  local member = nil -- the typed member a description would belong to

  local function claim_at(lnum, body, kind)
    local target, user, date, hash = body:match(STAMP_PAT)
    local claim = {
      kind = kind,
      target = target and vim.trim(target) or body,
      desc = {},
      stamp = user and { user = user:sub(2), date = date, hash = hash } or nil,
      lnum = lnum,
      feature = feature.name,
    }
    table.insert(feature.claims, claim)
    table.insert(map.claims, claim)
    return claim
  end

  for lnum, line in ipairs(lines) do
    local name = line:match("^feature%s+(.+)$")
    if name then
      feature = { name = vim.trim(name), lnum = lnum, claims = {} }
      table.insert(map.features, feature)
      section, member = nil, nil
    elseif feature then
      local sec = line:match("^  (contains)%s*$")
        or line:match("^  (calls)%s*$")
        or line:match("^  (never)%s*$")
        or line:match("^  (exercises)%s*$")
      -- A TYPED MEMBER: `<kind> <name>` where a section header would be.
      --
      -- The kind must be one this project KNOWS, which is why parse takes a
      -- kind set. Without that test there is no telling a member from
      -- prose: `route /checklists/[slug]` and `Feature prose.` have the
      -- same shape, and guessing by shape alone silently turned the second
      -- word of a sentence into a claim. Prose is the default, as always —
      -- a line is grammar only when it demonstrably is.
      local mkind, mname = line:match("^  ([%w_]+)%s+(%S.*)$")
      local is_member = mkind ~= nil and known[mkind] ~= nil

      if sec then
        section, member = sec, nil
      elseif is_member then
        section, member = nil, claim_at(lnum, vim.trim(mname), mkind)
      elseif section and line:match("^    %S") then
        -- A claim under a legacy section header. `contains` was always
        -- doing two jobs and its shape said which, so reading it as the
        -- kind it meant is a renaming, not a reinterpretation.
        local body = line:match("^    (.-)%s*$")
        local kind = section
        if section == "contains" then
          kind = kinds.of_contains(body:match(STAMP_PAT) or body)
        end
        member = claim_at(lnum, body, kind)
      elseif member and line:match("^    %S") then
        -- Indented under a member with no section open: the member's own
        -- intent — what THIS member is for, as against what the feature is.
        member.desc[#member.desc + 1] = vim.trim(line)
      elseif not line:match("^%s*$") and not line:match("^    ") then
        -- A DEDENTED non-blank line ends the section; the line is prose.
        --
        -- A blank line deliberately does not. It reads like a terminator to a
        -- human, but treating it as one silently demotes every claim after it
        -- to prose — never checked, never rendered, and for a never-block,
        -- routed into the repo by glass.split. Indentation is the grammar;
        -- vertical space is layout.
        section, member = nil, nil
      end
      -- anything else: prose, preserved in lines, no model entry needed
    end
  end
  return map
end

--- The file a claim names, if it names one. `contains path:symbol` and
--- `exercises path[:label]` locate themselves; `calls` carries a hint, not
--- a path, and `never` is a pattern — neither contributes a location.
---
--- A `contains` target with NO symbol names the file itself. That exists
--- because divergence is file-level while footprints are symbol-derived, so
--- a file that defines nothing — a plugin/ bootstrap, a table of settings,
--- anything not lua — could be reported as unclaimed with no way to claim
--- it. An accusation you cannot act on is a bug in the report. The claim it
--- makes is correspondingly weak, and the verdict says which one it is.
---@param claim scry.Claim
---@return string?
function M.claim_path(claim, kinds)
  if claim.kind == "def" then
    return claim.target:match("^(.-):[%w_.]+$") or claim.target
  elseif claim.kind == "module" then
    return claim.target
  elseif claim.kind == "exercises" then
    return claim.target:match("^([^:]+):") or claim.target
  end
  -- A PATH-PROBED DECLARED KIND NAMES ITS FILE, and this used to say it
  -- could not: `route c/[slug]` located nothing, so divergence never counted
  -- src/pages/c/[slug].astro as described.
  --
  -- What that cost, on a real run: the page stayed in the undescribed
  -- worklist, so the next batch was asked about it again, so the drafter
  -- wrote another feature about it — and a claim's id carries its feature
  -- name, so the pass read each rewording as progress and never converged.
  -- 301 features over 60 targets, one route claimed by 73 of them, and a
  -- header reporting 24 files unclaimed while eleven of them were claimed
  -- dozens of times over.
  --
  -- The probe is a path template and the name is what fills it — the same
  -- substitution kinds.examples runs in reverse to discover names in the
  -- first place. A grep-probed kind still locates nothing, because a pattern
  -- is not a place; so do `never` and `calls`.
  local spec = kinds and kinds[claim.kind]
  if spec and spec.path then
    return require("scry.kinds").expand(spec.path, claim.target, "none")
  end
  return nil
end

--- The kinds in force for a project — builtins plus whatever it declared.
--- Every caller that parses a real project's map needs this, or a declared
--- kind reads as prose.
---@param root string?
---@return table<string, table>
function M.kinds_for(root)
  local config = root and require("scry.project").resolve(root) or {}
  return require("scry.kinds").all(config)
end

--- A feature's footprint: the files its located claims name, in order of
--- first appearance and deduplicated. Empty is meaningful — a feature that
--- locates nothing cannot scope a prohibition, and the resolver says so
--- rather than searching the whole project.
---@param feature scry.Feature
---@return string[]
function M.footprint(feature, kinds)
  local out, seen = {}, {}
  for _, claim in ipairs(feature.claims) do
    local path = M.claim_path(claim, kinds)
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
