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

-- WHAT REACH IS FOR, and why nobody was getting it.
--
-- Divergence counts a file as undescribed when no MEMBER names it. But a
-- file a feature's entry points genuinely reach is described by that
-- feature, whether or not anyone typed its name — that is the entire point
-- of computing reach, and it is the difference between a map of a real
-- project and eighty-six hand-listed paths.
--
-- The cache that divergence reads was only ever written by putting the
-- cursor on one feature and running a command. So the number in the header
-- was computed as though reach did not exist, for everyone who did not
-- know to make a per-feature gesture nobody would think to make.
--
-- It is computed for the whole map instead, in the background, when the
-- glass opens and when a draft lands. Measured on a real project: 1.6s to
-- index two languages. The cache carries a fingerprint, so a second look
-- costs nothing and a stale answer is discarded rather than trusted.
---@field state "off"|"running"|"done"|"unavailable"
M.progress = { state = "off" }

--- Compute and record reach for every feature in a map.
---
--- Best-effort by design: no engine, no answer, and the header says so
--- rather than presenting a reach-free count as the whole truth.
---@param root string
---@param map_ scry.Map
---@param cb fun(changed: boolean)?
function M.refresh(root, map_, cb)
  local sg = M.sg()
  if not sg then
    M.progress.state = "unavailable"
    if cb then
      cb(false)
    end
    return
  end
  if M.progress.state == "running" then
    return
  end
  M.progress.state = "running"

  sg.prepare(root, function()
    local left, changed = #map_.features, false
    if left == 0 then
      M.progress.state = "done"
      if cb then
        cb(false)
      end
      return
    end
    for _, feature in ipairs(map_.features) do
      M.of_feature(root, feature, function(files, resolved)
        vim.schedule(function()
          -- Only a RESOLVED answer is recorded. A guess would keep a file
          -- out of the unclaimed list on the strength of nothing.
          if resolved and #files > 0 then
            local cache = M.cache_load(root)
            cache[feature.name] = { files = files, at = os.time(), fingerprint = M.stamp(root, files) }
            M.cache_save(root, cache)
            changed = true
          end
          left = left - 1
          if left == 0 then
            M.progress.state = "done"
            if cb then
              cb(changed)
            end
          end
        end)
      end)
    end
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
