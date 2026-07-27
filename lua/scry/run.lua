-- :ScryExercise — the only thing in scry that executes your code.
--
-- Kept apart from checking on purpose. Every other verdict is a static read,
-- so re-computing it on every render costs nothing and can't surprise you.
-- Running a suite is slow, has side effects, and can hang; a tool that did it
-- whenever you opened a buffer is a tool you would stop opening. So the
-- separation is not laziness about performance — it is what keeps the glass
-- something you reach for.
local M = {}

--- Every distinct spec named by the map's `exercises` claims, each carrying
--- the UNION of the globs of every concern that exercises it. Two claims on
--- one file are one execution, and its recorded dependencies cover both
--- concerns' scopes — otherwise each would keep invalidating the other's
--- result.
---@param map_ scry.Map
---@param only_concern string? Restrict to one concern.
---@return { spec: string, globs: string[] }[]
function M.specs(map_, only_concern)
  local mapmod = require("scry.map")
  local out, index = {}, {}
  for _, claim in ipairs(map_.claims) do
    if claim.kind == "exercises" and (not only_concern or claim.concern == only_concern) then
      local spec = claim.target:match("^([^:]+):") or claim.target
      local entry = index[spec]
      if not entry then
        entry = { spec = spec, globs = {}, _seen = {} }
        index[spec] = entry
        out[#out + 1] = entry
      end
      local concern = mapmod.concern(map_, claim.concern)
      for _, g in ipairs(concern and concern.globs or {}) do
        if not entry._seen[g] then
          entry._seen[g] = true
          entry.globs[#entry.globs + 1] = g
        end
      end
    end
  end
  for _, e in ipairs(out) do
    e._seen = nil
  end
  return out
end

--- Run one spec and record the result. cb(run).
---
--- `deps` is fingerprinted as the run starts, and that fingerprint is what a
--- later check compares against to decide the result is still current.
---@param root string
---@param spec string
---@param config table
---@param deps string[] Repo-relative files this result depends on.
---@param cb fun(run: scry.Run)
function M.one(root, spec, config, deps, cb)
  local runs = require("scry.runs")
  local cmd = vim.deepcopy(config.test and config.test.cmd or {})
  if #cmd == 0 then
    cb(runs.record(root, spec, false, { "no test command configured — set test.cmd in setup()" }, deps))
    return
  end
  cmd[#cmd + 1] = spec

  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      -- Keep the tail of both streams: a runner may report failure on either,
      -- and the reason for a red claim is the whole value of recording it.
      local blob = (res.stdout or "") .. (res.stderr or "")
      local lines = vim.split(blob, "\n", { plain = true, trimempty = true })
      local tail = {}
      for i = math.max(1, #lines - 6), #lines do
        tail[#tail + 1] = lines[i]
      end
      cb(runs.record(root, spec, res.code == 0, tail, deps))
    end)
  end)
end

--- Run every spec the map exercises (or one concern's), then re-check.
---@param opts { concern: string? }?
function M.start(opts)
  opts = opts or {}
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  local config = require("scry").config
  local map_ = require("scry.map").parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false))
  local specs = M.specs(map_, opts.concern)
  if #specs == 0 then
    vim.notify("[scry] no exercises claims to run")
    return
  end
  if not (config.test and config.test.cmd and #config.test.cmd > 0) then
    vim.notify("[scry] no test command — set test = { cmd = {...} } in setup()", vim.log.levels.WARN)
    return
  end

  vim.notify(("[scry] running %d spec%s…"):format(#specs, #specs == 1 and "" or "s"))
  local runs = require("scry.runs")
  local prov = require("scry.provenance")
  local by_spec = {}
  for _, claim in ipairs(map_.claims) do
    if claim.kind == "exercises" then
      local sp = claim.target:match("^([^:]+):") or claim.target
      by_spec[sp] = by_spec[sp] or {}
      table.insert(by_spec[sp], claim)
    end
  end
  local pending, failed = #specs, {}
  for _, s in ipairs(specs) do
    local deps = runs.scope(state.root, s.globs)
    deps[#deps + 1] = s.spec
    M.one(state.root, s.spec, config, deps, function(run)
      if not run.ok then
        failed[#failed + 1] = s.spec
      end
      -- red-then-green under your own :ScryExercise is the trail for these claims
      for _, claim in ipairs(by_spec[s.spec] or {}) do
        prov.record(state.root, claim, run.ok and "green" or "red")
      end
      pending = pending - 1
      if pending == 0 then
        glass.check(function()
          if #failed > 0 then
            vim.notify(("[scry] %d failing: %s"):format(#failed, table.concat(failed, ", ")), vim.log.levels.WARN)
          else
            vim.notify(("[scry] %d spec%s passing"):format(#specs, #specs == 1 and "" or "s"))
          end
        end)
      end
    end)
  end
end

return M
