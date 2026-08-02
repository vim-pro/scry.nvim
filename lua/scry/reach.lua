-- Reach: what a feature actually touches, computed rather than listed.
--
-- This is the piece that decides whether a map stays readable. A feature's
-- members are its ENTRY POINTS — the route someone visits, the endpoint a
-- client calls — and the code behind them is not something anyone should
-- have to enumerate. Drafted over a real project without this, scry produced
-- eighty-six hand-listed members; the archived vim.pro's manifests, which
-- had it, ran to fifteen lines and said more.
--
-- IT FOLLOWS FILES, NOT NAMES. See lua/scry/imports.lua. The short version:
-- this was built twice on name resolvers — stack graphs, then a language
-- server — and both answered a harder question than the one being asked, in
-- exchange for only answering it in languages someone had written a grammar
-- for. Divergence consumes a list of paths. An import specifier and a path
-- join produce that list, for astro and Lua and anything else that borrowed
-- the syntax, with no engine to install and no index to build.
local M = {}

-- ---------------------------------------------------------------------------
-- The cache, and why reach is stored at all
--
-- Less critical than it was — a closure is file reads now rather than
-- subprocesses — but still worth keeping, because |scry-divergence| runs on
-- every check and a check has to stay cheap enough to run every time you
-- look.
--
-- It carries a fingerprint of the files it was computed from, because a
-- stale reach is worse than none: it would keep a file out of the unclaimed
-- list on the strength of an import that has since been deleted.
-- ---------------------------------------------------------------------------

--- Cache file for a root. Machine-local, like runs — reach is a fact about
--- this checkout, not something to commit.
---@param root string
---@return string
function M.cache_path(root)
  local dir = vim.fn.stdpath("state") .. "/scry/reach"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(root, ":p"):gsub("[/\\:]", "%%") .. "json"
end

---@param root string
---@return table<string, { files: string[], at: integer, fingerprint: string }>
function M.cache_load(root)
  local f = io.open(M.cache_path(root), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  return (ok and type(decoded) == "table") and decoded or {}
end

---@param root string
---@param cache table
function M.cache_save(root, cache)
  local f = io.open(M.cache_path(root), "w")
  if f then
    f:write(vim.json.encode(cache))
    f:close()
  end
end

--- A deterministic stamp for a set of files.
---
--- runs.fingerprint returns a TABLE, and comparing two tables with ~= compares
--- identities, so a cache guarded that way is never valid and never used —
--- the reach was computed, written, and then silently ignored on every read.
--- Nothing errored; divergence just never shrank. Sorted and flattened to a
--- string, it compares by value.
---@param root string
---@param files string[]
---@return string
function M.stamp(root, files)
  local runs = require("scry.runs")
  local sorted = vim.deepcopy(files)
  table.sort(sorted)
  local parts = {}
  for _, p in ipairs(sorted) do
    parts[#parts + 1] = p .. "=" .. tostring(runs.mark(root, p))
  end
  return table.concat(parts, ";")
end

--- The reach recorded for a feature, or nil when there is none or it has gone
--- stale. Staleness is by fingerprint over the reached files: if any changed,
--- the import that put them there may not exist any more, and keeping a file
--- out of the unclaimed list on a deleted import is the one failure a cache
--- here can cause.
---@param root string
---@param feature_name string
---@return string[]?
function M.cached(root, feature_name)
  local entry = M.cache_load(root)[feature_name]
  if not entry or type(entry.files) ~= "table" then
    return nil
  end
  if entry.fingerprint ~= M.stamp(root, entry.files) then
    return nil
  end
  return entry.files
end

-- ---------------------------------------------------------------------------
-- The questions
-- ---------------------------------------------------------------------------

--- The files a feature ENTERS BY.
---
--- EVERY MEMBER THAT NAMES A FILE IS A DOOR. This took only `def` and
--- `module` members, which is a vocabulary from before kinds existed — and on
--- a project whose map is nine `route` members it meant a feature had no
--- doors at all, so its reach was empty and divergence never shrank. A route
--- names src/pages/{name}.astro; that is a door.
---
--- Relations are not doors. A `never` names a pattern rather than a place,
--- and an `exercises` names the spec that CHECKS the feature rather than the
--- code that IS it — following that would pull the test suite into the
--- product's own footprint.
---@param feature scry.Feature
---@param kinds table<string, table>? the kinds in force, for path-probed members
---@return string[]
function M.entry_points(feature, kinds)
  local mapmod = require("scry.map")
  local RELATION = require("scry.kinds").RELATION
  local seen, out = {}, {}
  for _, claim in ipairs(feature.claims) do
    if not RELATION[claim.kind] then
      local path = mapmod.claim_path(claim, kinds)
      if path and not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  table.sort(out)
  return out
end

--- A feature's whole footprint: everything its entry points reach.
---
--- Synchronous, which neither resolver this replaced could be. A hop is a
--- file read.
---@param root string
---@param feature scry.Feature
---@param kinds table<string, table>?
---@return string[] files
---@return boolean resolved false when not one entry point could be read
function M.of_feature(root, feature, kinds)
  local seeds = M.entry_points(feature, kinds)
  if #seeds == 0 then
    return {}, true
  end
  return require("scry.imports").closure(root, seeds)
end

--- Compute and record a whole feature's reach.
---@param root string
---@param feature scry.Feature
---@param kinds table<string, table>?
function M.feature_show(root, feature, kinds)
  local files, resolved = M.of_feature(root, feature, kinds)
  if #files == 0 then
    vim.notify(("[scry] %s enters by nothing scry can follow"):format(feature.name))
    return
  end
  -- Only a readable answer is recorded. A guess must never excuse a file
  -- from the unclaimed list.
  if resolved then
    local cache = M.cache_load(root)
    cache[feature.name] = {
      files = files,
      at = os.time(),
      fingerprint = M.stamp(root, files),
    }
    M.cache_save(root, cache)
  end
  vim.notify(
    ("[scry] %s reaches %d file(s)%s"):format(
      feature.name,
      #files,
      resolved and " — recorded, and divergence will count them" or " — UNREADABLE, not recorded"
    )
  )
end

-- ---------------------------------------------------------------------------
-- Reach for the WHOLE map, in the background
--
-- The cache divergence reads was once only ever written by putting the
-- cursor on one feature and running a command. So the number in the header
-- was computed as though reach did not exist, for everyone who did not know
-- to make a per-feature gesture nobody would think to make.
--
-- It is computed for the whole map instead, when the glass opens and when a
-- draft lands. That used to mean indexing two languages and waiting 1.6s;
-- following imports it is file reads, so the wait is gone and only the
-- scheduling remains — the glass renders first, reach lands after.
-- ---------------------------------------------------------------------------

---@field state "off"|"running"|"done"
M.progress = { state = "off" }

--- Compute and record reach for every feature in a map.
---@param root string
---@param map_ scry.Map
---@param cb fun(changed: boolean)?
function M.refresh(root, map_, cb)
  if M.progress.state == "running" then
    return
  end
  M.progress.state = "running"
  local kinds = require("scry.map").kinds_for(root)

  vim.schedule(function()
    local cache, changed = M.cache_load(root), false
    for _, feature in ipairs(map_.features) do
      local files, resolved = M.of_feature(root, feature, kinds)
      -- Only a READABLE answer is recorded. A guess would keep a file out of
      -- the unclaimed list on the strength of nothing.
      if resolved and #files > 0 then
        local stamp = M.stamp(root, files)
        local prev = cache[feature.name]
        -- Compared by fingerprint rather than assumed: this reported a change
        -- on every pass otherwise, so the glass re-rendered each time reach
        -- ran and found exactly what it found last time.
        if not prev or prev.fingerprint ~= stamp then
          changed = true
        end
        cache[feature.name] = { files = files, at = os.time(), fingerprint = stamp }
      end
    end
    if changed then
      M.cache_save(root, cache)
    end
    M.progress.state = "done"
    if cb then
      cb(changed)
    end
  end)
end

--- :ScryReach — what the line under the cursor is connected to.
---
--- On a FEATURE, outbound: everything it enters by, unioned and recorded, so
--- divergence stops asking you to name files your entry points already cover.
---
--- On a MEMBER, inbound: which files pull that member's file in. That is the
--- blast radius of changing it, at the altitude scry works at — a file rather
--- than a symbol, which is the grain a feature is made of and the only grain
--- that exists for a .astro route at all.
function M.show()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf and state.root) then
    vim.notify("[scry] :ScryReach works on a feature or a member in the glass", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local kinds = mapmod.kinds_for(state.root)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), kinds)

  for _, f in ipairs(map_.features) do
    if f.lnum == lnum then
      M.feature_show(state.root, f, kinds)
      return
    end
  end

  local claim
  for _, c in ipairs(map_.claims) do
    if c.lnum == lnum then
      claim = c
    end
  end
  if not claim then
    vim.notify("[scry] reach is a question about a feature or a member", vim.log.levels.WARN)
    return
  end

  local path = mapmod.claim_path(claim, kinds)
  if not path then
    vim.notify(("[scry] %s names no file to trace"):format(claim.target), vim.log.levels.WARN)
    return
  end

  local users = require("scry.imports").importers(state.root, path)
  if #users == 0 then
    vim.notify(("[scry] nothing in this project imports %s"):format(path))
    return
  end
  local items = {}
  for _, u in ipairs(users) do
    items[#items + 1] = { filename = u, lnum = 1, col = 1, text = "imports " .. path }
  end
  vim.fn.setqflist({}, " ", { title = ("scry: what imports %s"):format(path), items = items })
  vim.notify(("[scry] %s is imported by %d file(s) — :copen"):format(path, #users))
end

return M
