-- What a file pulls in, resolved to files in this repository.
--
-- NOT NAME RESOLUTION, and that distinction is the whole reason this exists.
--
-- The question |scry-divergence| asks is "does this entry point pull in this
-- file". Binding a NAME to its definition needs a grammar and a scope model
-- for every language you support. Following a FILE needs the import
-- specifier and the filesystem. The second question is the one being asked,
-- and it is enormously cheaper.
--
-- IT ALSO ANSWERS FOR FILE TYPES NOTHING ELSE DOES. checklists.org's map is
-- nine `route` members and every one of them is a .astro file. No
-- stack-graphs grammar covers astro; no language server here does either. So
-- reach from a route computed nothing at all — on the project the whole
-- design was built for. This reads `from '../lib/db.js'` out of an astro
-- file without knowing what astro is, because a quoted specifier after
-- `from` looks the same in every language that borrowed the syntax.
--
-- It answers for Lua too, where scry's own map lives. `require("scry.map")`
-- is a module path, and a module path is a file path with the dots swapped.
--
-- ONLY FIRST-PARTY SPECIFIERS ARE FOLLOWED. A bare specifier — `react`,
-- `node:fs` — resolves into node_modules or the standard library, which is
-- not code this project is answerable for and not anywhere a footprint
-- should wander.
--
-- No subprocess, no index, no server. A file's imports are a read and a
-- handful of pattern matches, so a whole closure costs less than one
-- ripgrep did.
local M = {}

-- Extensions tried when a specifier does not name one, in preference order.
-- Astro and the component formats are here for the same reason the module
-- exists: they are what real entry points are written in.
M.EXTENSIONS = {
  ".ts", ".tsx", ".mts", ".cts",
  ".js", ".jsx", ".mjs", ".cjs",
  ".astro", ".svelte", ".vue",
  ".py", ".rb", ".go", ".lua",
  ".json",
}

--- Every import specifier in a file, in source order.
---
--- Four shapes, which between them cover ESM, CommonJS, dynamic import and
--- Lua. A specifier is whatever sits in the quotes; what it MEANS is
--- M.resolve's problem.
---@param text string file contents
---@return string[]
function M.specifiers(text)
  local out, seen = {}, {}
  local function add(s)
    if s ~= "" and not seen[s] then
      seen[s] = true
      out[#out + 1] = s
    end
  end
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    -- A LINE THAT STARTS AS A COMMENT IS A COMMENT, and this is not
    -- fastidiousness. Without it, this very file was reported as importing
    -- scry.map, on the strength of a doc comment containing the words
    -- `require("scry.map")` — and because that module really exists, nothing
    -- downstream dropped it. A file excused from the unclaimed list by a
    -- sentence in a comment is precisely the over-claim scry exists to
    -- prevent.
    --
    -- Only leading markers, deliberately. Deciding whether a `//` halfway
    -- along a line is a comment or part of a URL means lexing the language,
    -- which is the cost this module was written to avoid. An import inside a
    -- trailing comment or a /* block */ is still counted; that is a known
    -- edge and it over-reports rather than misses.
    local first = line:match("^%s*(%S%S?)") or ""
    local commented = first:sub(1, 2) == "--"
      or first:sub(1, 2) == "//"
      or first:sub(1, 1) == "#"
      or first:sub(1, 1) == "*"
    if not commented then
    for s in line:gmatch("from%s+['\"]([^'\"]+)['\"]") do
      add(s)
    end
    for s in line:gmatch("import%s+['\"]([^'\"]+)['\"]") do
      add(s)
    end
    for s in line:gmatch("import%s*%(%s*['\"]([^'\"]+)['\"]") do
      add(s)
    end
    for s in line:gmatch("require%s*%(?%s*['\"]([^'\"]+)['\"]") do
      add(s)
    end
    end
  end
  return out
end

--- Is this a specifier naming something in this project, as against a
--- package or a standard-library module?
---
--- Relative is first-party. Everything else is not, and the ones that look
--- like a Lua module path are decided by M.resolve finding a file for them —
--- `scry.map` and `plenary.async` are the same shape, and only one of them
--- is in this repo.
---@param spec string
---@return boolean
function M.is_relative(spec)
  return spec:sub(1, 2) == "./" or spec:sub(1, 3) == "../"
end

--- Collapse `.` and `..` in a repo-relative path. Returns nil if it climbs
--- out of the repository, which is a specifier pointing at something this
--- project does not contain.
---@param path string
---@return string?
function M.normalize(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then
      if #parts == 0 then
        return nil
      end
      table.remove(parts)
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return table.concat(parts, "/")
end

---@param root string
---@param rel string repo-relative
---@return boolean
local function exists(root, rel)
  return vim.fn.filereadable(root .. "/" .. rel) == 1
end

--- Candidate paths for a base, in the order a bundler would try them.
---@param base string
---@return string[]
local function probes(base)
  local out = { base }
  for _, ext in ipairs(M.EXTENSIONS) do
    out[#out + 1] = base .. ext
  end
  for _, ext in ipairs(M.EXTENSIONS) do
    out[#out + 1] = base .. "/index" .. ext
  end
  return out
end

--- Resolve one specifier to a file in this repo, or nil.
---
--- THE `.js` THAT MEANS `.ts` IS HANDLED HERE, and it is the single case
--- that mattered most. Under ESM you import `./db.js` and the file on disk
--- is `db.ts` — TypeScript's own rule, and the exact chain a stack-graphs
--- grammar failed to follow on a real project. Here it is three lines: strip
--- the extension the specifier claims, probe the ones that could satisfy it.
---@param root string
---@param from string the importing file, repo-relative
---@param spec string
---@return string?
function M.resolve(root, from, spec)
  local base
  if M.is_relative(spec) then
    local dir = from:match("^(.*)/[^/]*$") or ""
    base = M.normalize((dir == "" and spec or (dir .. "/" .. spec)))
  elseif spec:match("^[%w_][%w_.%-]*$") and spec:find("%.") then
    -- A Lua module path: dots are separators. `scry.map` -> lua/scry/map.lua
    base = "lua/" .. spec:gsub("%.", "/")
  else
    return nil
  end
  if not base or base == "" then
    return nil
  end

  for _, candidate in ipairs(probes(base)) do
    if exists(root, candidate) then
      return candidate
    end
  end
  -- The specifier named an extension that is not what is on disk. Strip it
  -- and try again — `./db.js` for `db.ts`.
  local stripped = base:match("^(.*)%.[%w]+$")
  if stripped then
    for _, candidate in ipairs(probes(stripped)) do
      if exists(root, candidate) then
        return candidate
      end
    end
  end
  return nil
end

--- The files this file imports, one hop.
---
--- Synchronous, because it is a read and some pattern matches. Every other
--- resolver scry has had needed a subprocess or a live server for this.
---@param root string
---@param path string repo-relative
---@return string[] files
---@return boolean readable whether the file could be read at all
function M.of(root, path)
  local f = io.open(root .. "/" .. path, "r")
  if not f then
    return {}, false
  end
  local text = f:read("*a")
  f:close()

  local out, seen = {}, { [path] = true }
  for _, spec in ipairs(M.specifiers(text)) do
    local hit = M.resolve(root, path, spec)
    if hit and not seen[hit] then
      seen[hit] = true
      out[#out + 1] = hit
    end
  end
  table.sort(out)
  return out, true
end

--- The files that import THIS one — the graph run backwards.
---
--- The inbound question, at the altitude scry actually works at. A symbol
--- resolver answers "who calls allChecklists"; this answers "which files
--- pull in db.js", which over-approximates that and never under-reports it.
--- For a tool whose nouns are features rather than functions, the file is
--- the useful grain — and unlike the symbol answer, this one exists for
--- astro and Lua.
---
--- Narrowed with ripgrep before anything is parsed. A file that imports
--- `src/lib/db.js` must mention `db` in the specifier, so the stem is a
--- sound filter: it cannot miss an importer, and the files it lets through
--- are then parsed properly rather than trusted.
---@param root string
---@param path string repo-relative
---@return string[]
function M.importers(root, path)
  local base = path:match("([^/]+)$") or path
  local stem = base:match("^(.*)%.[%w]+$") or base
  local needles = { stem }
  -- `import '../comp/widget'` names the DIRECTORY, never the index file, so
  -- searching for `index` would find nothing that reaches it.
  if stem == "index" then
    local dir = path:match("([^/]+)/[^/]+$")
    if dir then
      needles = { dir }
    end
  end

  local args = { "rg", "--files-with-matches", "--fixed-strings" }
  for _, n in ipairs(needles) do
    args[#args + 1] = "-e"
    args[#args + 1] = n
  end
  local res = vim.system(args, { cwd = root, text = true }):wait()

  local out = {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    if line ~= path then
      for _, imported in ipairs(M.of(root, line)) do
        if imported == path then
          out[#out + 1] = line
          break
        end
      end
    end
  end
  table.sort(out)
  return out
end

--- Everything a set of files reaches, transitively.
---
--- Unbounded by default, and that is a deliberate difference from the
--- resolver this replaces. Depth was bounded there because each hop was a
--- subprocess; here a hop is a file read, so the honest stopping condition
--- is "nothing new", not "three".
---@param root string
---@param seeds string[] repo-relative
---@param opts { depth: integer? }?
---@return string[] files including the seeds
---@return boolean resolved false when not one seed could be read
function M.closure(root, seeds, opts)
  local limit = (opts or {}).depth
  local seen, frontier, any = {}, {}, false
  for _, s in ipairs(seeds) do
    if not seen[s] then
      seen[s] = true
      frontier[#frontier + 1] = s
    end
  end

  local depth = 0
  while #frontier > 0 and (not limit or depth < limit) do
    depth = depth + 1
    local next_ = {}
    for _, path in ipairs(frontier) do
      local files, readable = M.of(root, path)
      any = any or readable
      for _, f in ipairs(files) do
        if not seen[f] then
          seen[f] = true
          next_[#next_ + 1] = f
        end
      end
    end
    frontier = next_
  end

  local out = {}
  for p in pairs(seen) do
    out[#out + 1] = p
  end
  table.sort(out)
  return out, any
end

return M
