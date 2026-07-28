-- The run cache: where dynamic evidence lives between checks.
--
-- Every other verdict scry renders is a static read of a file — cheap, and
-- honest to recompute on every render. A test run is none of those: it is
-- slow, it has side effects, and it can hang. So `:Scry` must NEVER run
-- anything. Running is an explicit act (|:ScryExercise|); checking reads what the
-- last run left behind.
--
-- That buys correctness at the price of staleness, and staleness is the
-- whole danger of this evidence class: `✓ passing` from before your last
-- edit looks like the strongest verdict scry can render and is the easiest
-- one to be wrong. So a cached result is only reported as a pass while
-- nothing it depends on has changed since the run — otherwise it degrades to
-- "– stale", which lands in the unchecked column, where an unanswered claim
-- belongs.
local M = {}

---@class scry.Run
---@field spec string Repo-relative spec path that was run.
---@field at integer os.time() when the run finished.
---@field ok boolean Exit status was 0.
---@field output string[] Tail of combined output, for failure evidence.
---@field deps table<string, string> Fingerprint of every file the run
---  depended on, captured AS IT RAN. Staleness is a comparison against this,
---  not against the clock: mtimes have one-second granularity, so "edit, run"
---  completes inside a single tick and a timestamp comparison would call
---  every fresh run stale forever.

--- Cache file for a project root. Outside the repo, keyed like the holdout —
--- run results are machine-local facts, not something to commit.
---@param root string
---@return string
function M.path(root)
  local dir = vim.fn.stdpath("state") .. "/scry/runs"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(root, ":p"):gsub("[/\\:]", "%%") .. "json"
end

--- Load the whole cache for a root: { [spec] = scry.Run }.
---@param root string
---@return table<string, scry.Run>
function M.load(root)
  local f = io.open(M.path(root), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  return (ok and type(decoded) == "table") and decoded or {}
end

---@param root string
---@param runs table<string, scry.Run>
function M.save(root, runs)
  local f = io.open(M.path(root), "w")
  if not f then
    return
  end
  f:write(vim.json.encode(runs))
  f:close()
end

--- Identity of one file's current content-ish state: mtime and size. Cheap,
--- and enough to notice any edit that matters.
---@param root string
---@param rel string
---@return string
function M.mark(root, rel)
  local st = vim.loop.fs_stat(root .. "/" .. rel)
  return st and (st.mtime.sec .. ":" .. st.size) or "gone"
end

--- Fingerprint a set of repo-relative paths.
---@param root string
---@param paths string[]
---@return table<string, string>
function M.fingerprint(root, paths)
  local fp = {}
  for _, p in ipairs(paths) do
    fp[p] = M.mark(root, p)
  end
  return fp
end

--- Record one run, with the fingerprint of what it depended on.
---@param root string
---@param spec string
---@param ok boolean
---@param output string[]
---@param deps string[] Repo-relative paths this result depends on.
---@return scry.Run
function M.record(root, spec, ok, output, deps)
  local runs = M.load(root)
  runs[spec] = {
    spec = spec,
    at = os.time(),
    ok = ok,
    output = output,
    deps = M.fingerprint(root, deps or {}),
  }
  M.save(root, runs)
  return runs[spec]
end

--- Has anything this check cares about changed since the run?
---
--- Every dependency the CALLER names must match what the run recorded. A path
--- the run never saw counts as changed — the run didn't account for it, so it
--- can't vouch for it. Paths the run recorded but the caller doesn't ask about
--- are ignored, which is what lets two features with different scopes share
--- one spec without permanently invalidating each other.
---@param run scry.Run
---@param root string
---@param deps string[] Repo-relative paths the result depends on.
---@return boolean
function M.stale(run, root, deps)
  local fp = run.deps
  if type(fp) ~= "table" then
    return true -- a run from before fingerprints existed can't be trusted
  end
  for _, d in ipairs(deps) do
    if fp[d] ~= M.mark(root, d) then
      return true
    end
  end
  return false
end

--- Expand a feature's globs to repo-relative files (via rg, which already
--- speaks the glob syntax the map documents). Synchronous and small: this
--- runs at check time over one feature.
---@param root string
---@param globs string[]
---@return string[]
function M.scope(root, globs)
  local args = { "rg", "--files" }
  for _, g in ipairs(globs or {}) do
    args[#args + 1] = "-g"
    args[#args + 1] = g
  end
  local res = vim.system(args, { cwd = root, text = true }):wait()
  if res.code ~= 0 then
    return {}
  end
  local files = {}
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true, trimempty = true })) do
    files[#files + 1] = line
  end
  return files
end

return M
