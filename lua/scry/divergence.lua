-- Divergence: the code no feature claims.
--
-- Murphy's reflexion model has three verdicts, and until now scry had two.
-- Convergence is `✓ defined`; absence is `✗ absent`; DIVERGENCE is reality
-- the model does not account for. Without it a map cannot be read honestly:
-- every feature can be done and the map still describe a tenth of the
-- product, and nothing on the page would say so.
--
-- ALTITUDE, again. The obvious implementation — enumerate every definition
-- and list the unclaimed ones — is the mistake vim-pro already made and
-- documented: its own product buffer rendered 97 functions including
-- `chomp`, `clip`, and `stat`, which is the implementation wearing a
-- product's clothes. Definitions are far too numerous to list wholesale, so
-- divergence here is FILE-level. "lua/auth/tokens.lua is covered by no
-- feature" is a sentence you can act on: either add a claim to a feature
-- that should own it, or name the feature nobody has written down.
--
-- The result is deliberately blunt: a file counts as claimed only if some
-- feature's footprint names it. A file a feature genuinely uses but never
-- names still reads as unclaimed — which is correct. The map's job is to
-- say what the product does; silence about a file is silence.
local M = {}

--- Every file scry considers claimable, repo-relative.
---
--- Empty `sources` means "everything ripgrep lists", which respects
--- .gitignore and is the honest default: scry does not know which of your
--- files are product. Narrow it in setup() when the noise outweighs the
--- signal — and the fact that you had to is itself information.
---@param root string
---@param config table
---@return string[]
function M.sources(root, config)
  local globs = (config.sources and #config.sources > 0) and config.sources or nil
  local args = { "rg", "--files" }
  for _, g in ipairs(globs or {}) do
    args[#args + 1] = "-g"
    args[#args + 1] = g
  end
  local res = vim.system(args, { cwd = root, text = true }):wait()
  if res.code ~= 0 then
    return {}
  end
  local out = {}
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true, trimempty = true })) do
    out[#out + 1] = line
  end
  return out
end

-- scry's own bookkeeping is not product. Excluded by path rather than by
-- config so a fresh map never opens accusing you of not describing itself.
---@param path string
---@param config table
---@return boolean
local function is_scry_own(path, config)
  if path == config.map_path then
    return true
  end
  if config.holdout_path and config.holdout_path ~= "" and path == config.holdout_path then
    return true
  end
  return path:match("^%.scry/") ~= nil
end

--- Files no feature's footprint names.
---@param root string
---@param map_ scry.Map
---@param config table
---@return string[] unclaimed, integer total  (total = claimable files seen)
function M.unclaimed(root, map_, config)
  local mapmod = require("scry.map")
  local reach = require("scry.reach")
  local claimed = {}
  for _, feature in ipairs(map_.features) do
    for _, path in ipairs(mapmod.footprint(feature)) do
      claimed[path] = true
    end
    -- ...and whatever this feature's entry points genuinely REACH, when
    -- |:ScryReach| has computed it and the files have not moved since.
    --
    -- This is the point of reach. A file a feature's defs bind to is
    -- described by that feature whether or not anyone typed its name, and
    -- making someone type it is what turned a map of a real project into
    -- eighty-six hand-listed members. Only a RESOLVED answer counts: a name
    -- match would quietly excuse every file that happens to mention a
    -- common word, which is the opposite of what this list is for.
    for _, path in ipairs(reach.cached(root, feature.name) or {}) do
      claimed[path] = true
    end
  end

  local out, total = {}, 0
  for _, path in ipairs(M.sources(root, config)) do
    if not is_scry_own(path, config) then
      total = total + 1
      if not claimed[path] then
        out[#out + 1] = path
      end
    end
  end
  return out, total
end

--- Put the unclaimed files in the quickfix list, so the thing you do next
--- happens where every other list of work happens.
function M.to_quickfix()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local files, total = M.unclaimed(state.root, map_, require("scry.project").resolve(state.root))
  if #files == 0 then
    vim.notify(("[scry] every one of %d files is claimed by a feature"):format(total))
    return
  end
  local items = {}
  for _, path in ipairs(files) do
    items[#items + 1] = {
      filename = path,
      lnum = 1,
      col = 1,
      text = "no feature claims this file",
      user_data = { scry = { unclaimed = true } },
    }
  end
  vim.fn.setqflist({}, " ", { title = "scry: unclaimed by any feature", items = items })
  vim.notify(("[scry] %d of %d files unclaimed — :copen"):format(#files, total))
end

return M
