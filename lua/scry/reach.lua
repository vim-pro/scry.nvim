-- Reach: what a feature actually touches, computed rather than listed.
--
-- This is the piece that decides whether a map stays readable. A feature's
-- members are its ENTRY POINTS — the route someone visits, the command they
-- run — and the code behind them is not something anyone should have to
-- enumerate. Drafted over a real project without this, scry produced
-- eighty-six hand-listed members; the archived vim.pro's manifests, which
-- had it, ran to fifteen lines and said more.
--
-- THE RESOLVING ITSELF NOW LIVES ELSEWHERE. stackgraphs.nvim answers four
-- questions — what a name binds to, what binds to a definition, what a file
-- reaches, and the transitive closure of that — and every answer carries a
-- fidelity that scry may not render a stronger word than. That seam exists
-- because the engine behind it is unmaintained upstream and covers five
-- languages: a good thing to depend on, a bad thing to have scry's
-- vocabulary shaped by.
--
-- So what is left here is the part that is scry's: which files a FEATURE
-- enters by, and whether an answer is worth writing down. The cache is the
-- interesting half — see below for why a stale reach is worse than none.
local M = {}

--- stackgraphs.nvim, or nil.
---
--- Optional rather than required. Without it every verdict scry gives still
--- works — kinds are probed by path and grep, `def` by treesitter — and only
--- reach goes away. Erroring at load would take a working tool off someone
--- for a feature they may not use.
---@return table?
function M.sg()
  local ok, mod = pcall(require, "stackgraphs")
  return ok and mod or nil
end

local MISSING = "[scry] reach needs stackgraphs.nvim (vim-pro/stackgraphs.nvim)"

-- ---------------------------------------------------------------------------
-- The cache, and why reach is stored at all
--
-- Reach is expensive: indexing a project is the slowest thing scry does. A
-- check has to stay cheap enough to run every time you look, so reach cannot
-- be part of one. But its ANSWER is exactly what |scry-divergence| needs — a
-- file a feature's entry points genuinely reach is described by that
-- feature, whether or not anyone listed it.
--
-- So the answer is written down, out of the repo alongside the run cache,
-- and divergence reads it. It carries a fingerprint of the files it was
-- computed from, because a stale reach is worse than none: it would keep a
-- file out of the unclaimed list on the strength of a binding that has since
-- been deleted.
-- ---------------------------------------------------------------------------

--- Cache file for a root. Machine-local, like runs — a resolved binding is a
--- fact about this checkout, not something to commit.
---
--- Callers must be on the main loop: this uses vim.fn, which a vim.system
--- callback's fast event context forbids.
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
--- stale. Staleness is by fingerprint over the reached files: if any of them
--- changed, the binding that put them there may not exist any more, and
--- keeping a file out of the unclaimed list on a deleted binding is the one
--- failure a cache here can cause.
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
-- The questions scry asks
-- ---------------------------------------------------------------------------

--- The files a feature ENTERS BY: the paths of its def and module members.
---
--- This is the only part of reach that knows what a feature is, and it is
--- deliberately small — everything downstream is a question about paths.
---@param feature scry.Feature
---@return string[]
function M.entry_points(feature)
  local seen, out = {}, {}
  for _, claim in ipairs(feature.claims) do
    local path = require("scry.map").claim_path(claim)
    if path and (claim.kind == "def" or claim.kind == "module") and not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

--- A feature's whole footprint: everything its entry points reach.
---@param root string
---@param feature scry.Feature
---@param cb fun(files: string[], resolved: boolean)
function M.of_feature(root, feature, cb)
  local sg = M.sg()
  local seeds = M.entry_points(feature)
  if #seeds == 0 then
    cb({}, true)
    return
  end
  if not sg then
    cb({}, false)
    return
  end
  sg.closure(root, seeds, nil, function(answer)
    cb(answer.files, answer.fidelity == sg.RESOLVED)
  end)
end

--- Compute and record a whole feature's reach.
---@param root string
---@param feature scry.Feature
function M.feature_show(root, feature)
  local sg = M.sg()
  if not sg then
    vim.notify(MISSING, vim.log.levels.WARN)
    return
  end
  sg.prepare(root, function()
    M.of_feature(root, feature, function(files, resolved)
      vim.schedule(function()
        if #files == 0 then
          vim.notify(("[scry] %s reaches nothing scry can see"):format(feature.name))
          return
        end
        -- Only a resolved answer is recorded. A name match must never excuse
        -- a file from the unclaimed list.
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
            resolved and " — recorded, and divergence will count them" or " — UNRESOLVED, not recorded"
          )
        )
      end)
    end)
  end)
end

--- :ScryReach — everything that binds to the def under the cursor, into the
--- quickfix list.
---
--- The quickfix list because that is where every list of places goes in this
--- family, and because quickfix-pro decorates it. The TITLE carries the
--- fidelity: a reader has to be able to tell a resolved answer from a textual
--- one without remembering which engines are installed.
function M.show()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf and state.root) then
    vim.notify("[scry] :ScryReach works on a claim in the glass", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local claim
  for _, c in ipairs(map_.claims) do
    if c.lnum == lnum then
      claim = c
    end
  end
  -- On a FEATURE line: the reach of everything it enters by, unioned and
  -- recorded, so divergence stops asking you to name files your entry points
  -- already reach.
  if not claim then
    for _, f in ipairs(map_.features) do
      if f.lnum == lnum then
        M.feature_show(state.root, f)
        return
      end
    end
  end
  if not claim or claim.kind ~= "def" then
    vim.notify("[scry] reach is a question about a def or a feature", vim.log.levels.WARN)
    return
  end
  local path, name = claim.target:match("^(.-):([%w_.]+)$")
  if not path then
    vim.notify("[scry] " .. claim.target .. " names no symbol to trace", vim.log.levels.WARN)
    return
  end
  name = name:match("([%w_]+)$") or name

  local sg = M.sg()
  if not sg then
    vim.notify(MISSING, vim.log.levels.WARN)
    return
  end
  local target_lnum = require("scry.resolvers.ts_rg").locate(state.root, path, name) or 1

  sg.prepare(state.root, function()
    sg.references(state.root, { path = path, lnum = target_lnum, name = name }, function(a)
      vim.schedule(function()
        if a.n == 0 then
          vim.notify(("[scry] nothing reaches %s (%s)"):format(claim.target, a.fidelity))
          return
        end
        local items = {}
        for _, h in ipairs(a.hits) do
          items[#items + 1] = { filename = h.path, lnum = h.lnum, col = h.col, text = name }
        end
        -- The fidelity comes from the engine and is rendered as it arrived.
        -- The glass may never say a stronger word than it was handed, and
        -- neither may this.
        local how = a.fidelity == sg.RESOLVED and "resolved"
          or ("%s only — %s"):format(a.fidelity, a.reason or "a name match, not a reference")
        vim.fn.setqflist({}, " ", {
          title = ("scry: reach of %s (%s)"):format(claim.target, how),
          items = items,
        })
        vim.notify(("[scry] %s: %d reference(s) in %d file(s) — %s — :copen"):format(claim.target, a.n, a.files, how))
      end)
    end)
  end)
end

--- A one-line account of what reach is available here, for :checkhealth.
---@return string[]
function M.status()
  local sg = M.sg()
  if not sg then
    return { "stackgraphs.nvim: not installed — reach is unavailable" }
  end
  return sg.status()
end

return M
