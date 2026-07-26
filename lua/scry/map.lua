-- The map: plain text in, structure out, plain text back — byte-identical.
--
-- The model keeps the ORIGINAL lines and parses an overlay of references
-- into them (concerns, sections, claims, each carrying its line number).
-- Serialization returns the lines array, so a parse→serialize round trip
-- cannot lose anything: operations that change the map (stamping a claim)
-- edit the line in place and re-parse.
--
-- There are no parse errors. A line is a concern header, a files line, a
-- section header, a claim (when inside a section), or prose. Prose is
-- preserved verbatim, never checked, never marked.
local M = {}

---@class scry.Stamp
---@field user string  From the "@name" token.
---@field date string  YYYY-MM-DD.
---@field hash string  6 hex chars of sha256(target).

---@class scry.Claim
---@field kind "contains"|"calls"|"never"
---@field target string Trimmed claim text, stamp excluded. The canonical
---  form hashed by ratification.
---@field stamp scry.Stamp?
---@field lnum integer 1-based line in the parsed lines array.
---@field concern string

---@class scry.Concern
---@field name string
---@field lnum integer
---@field globs string[] From the "files" line ({} if none).
---@field claims scry.Claim[]

---@class scry.Map
---@field lines string[] The source of truth; serialize() returns these.
---@field concerns scry.Concern[]
---@field claims scry.Claim[] All claims across concerns, in order.

-- A claim line's optional ratification suffix. The "  -- @" separator is
-- reserved: a never-pattern that needs a literal "-- @user date hex"
-- tail would collide, and the docs say so.
local STAMP_PAT = "^(.-)%s+%-%- (@%S+) (%d%d%d%d%-%d%d%-%d%d) (%x%x%x%x%x%x)%s*$"

---@param lines string[]
---@return scry.Map
function M.parse(lines)
  local map = { lines = lines, concerns = {}, claims = {} }
  local concern = nil
  local section = nil -- current claim kind, or nil

  for lnum, line in ipairs(lines) do
    local name = line:match("^# (.+)$")
    if name then
      concern = { name = vim.trim(name), lnum = lnum, globs = {}, claims = {} }
      table.insert(map.concerns, concern)
      section = nil
    elseif concern then
      local globs = line:match("^  files%s+(.+)$")
      local sec = line:match("^  (contains)%s*$") or line:match("^  (calls)%s*$") or line:match("^  (never)%s*$")
      if globs then
        for g in globs:gmatch("[^,]+") do
          table.insert(concern.globs, vim.trim(g))
        end
        section = nil
      elseif sec then
        section = sec
      elseif section and line:match("^    %S") then
        local body = line:match("^    (.-)%s*$")
        local target, user, date, hash = body:match(STAMP_PAT)
        local claim = {
          kind = section,
          target = target and vim.trim(target) or body,
          stamp = user and { user = user:sub(2), date = date, hash = hash } or nil,
          lnum = lnum,
          concern = concern.name,
        }
        table.insert(concern.claims, claim)
        table.insert(map.claims, claim)
      elseif line:match("^%s*$") or not line:match("^    ") then
        -- blank or dedented line ends the section; the line itself is prose
        section = nil
      end
      -- anything else: prose, preserved in lines, no model entry needed
    end
  end
  return map
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

--- Find a concern by name.
---@param map scry.Map
---@param name string
---@return scry.Concern?
function M.concern(map, name)
  for _, c in ipairs(map.concerns) do
    if c.name == name then
      return c
    end
  end
end

--- Stable identity for a claim (report keys, cross-render matching).
---@param claim scry.Claim
---@return string
function M.claim_id(claim)
  return claim.concern .. "\1" .. claim.kind .. "\1" .. claim.target
end

return M
