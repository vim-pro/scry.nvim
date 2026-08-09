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
  -- SORTED, because ripgrep's is not an order. It walks directories in
  -- parallel and emits paths as workers finish them, so the same project
  -- lists differently between runs and between machines.
  --
  -- Everything downstream inherits that. A draft pass takes the first twelve
  -- unclaimed files, so which twelve you are asked about is a coin flip; run
  -- the pass twice and it walks the codebase differently both times, with no
  -- way to tell where you are in it. Sorting makes a batch a position in a
  -- list rather than a sample from one.
  table.sort(out)
  return out
end

-- FILES NO FEATURE COULD EVER CLAIM. Excluded categorically, not by
-- config, because the exclusion is not a judgment about a particular
-- project: an icon has no behavior to describe, and a lockfile is a
-- record of a resolver's arithmetic. Asking someone to account for them
-- is the same mistake as asking them to describe .scry/ — which is why it
-- sits beside that rule rather than in `sources`.
--
-- `sources` remains the place to say what THIS product is made of, and it
-- is a different question. This list is only about files where the answer
-- can never be yes.
--
-- It is not free to get wrong in either direction, so it is short. Source
-- that happens to be generated, content that happens to be markdown, and
-- build config are all left in: a reader may reasonably decide any of them
-- is part of the product, and scry has no business deciding first.
--
-- Measured on a real project: seventy-two files, of which eight were these.
-- The cost was not the eight. It was that a drafting pass kept being handed
-- them, could not describe them, and correctly concluded it had stopped
-- making progress.
local UNDESCRIBABLE = {
  -- assets: pictures, fonts, media
  "%.png$",
  "%.jpe?g$",
  "%.gif$",
  "%.webp$",
  "%.avif$",
  "%.ico$",
  "%.svg$",
  "%.woff2?$",
  "%.ttf$",
  "%.otf$",
  "%.eot$",
  "%.mp4$",
  "%.webm$",
  "%.mp3$",
  "%.wav$",
  -- a lockfile is a resolver's output, not a decision anyone made
  "^package%-lock%.json$",
  "/package%-lock%.json$",
  "^yarn%.lock$",
  "/yarn%.lock$",
  "^pnpm%-lock%.yaml$",
  "/pnpm%-lock%.yaml$",
  "^bun%.lockb$",
  "^Cargo%.lock$",
  "/Cargo%.lock$",
  "^poetry%.lock$",
  "^uv%.lock$",
  "^Gemfile%.lock$",
  "^composer%.lock$",
  "^go%.sum$",
  "/go%.sum$",
}

--- Could a feature ever claim this file?
---@param path string
---@return boolean
function M.describable(path)
  for _, pat in ipairs(UNDESCRIBABLE) do
    if path:match(pat) then
      return false
    end
  end
  return true
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
    for _, path in ipairs(mapmod.footprint(feature, require("scry.kinds").all(config))) do
      claimed[path] = true
    end
    -- ...and whatever this feature's entry points genuinely REACH, when
    -- reach has computed it and the files have not moved since.
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
    if not is_scry_own(path, config) and M.describable(path) then
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
--- Roll a list of paths up to the shallowest grouping that a person can
--- act on.
---
--- SCALE IS NOT SPEED HERE. Measured on a twenty-thousand-file project,
--- divergence itself takes 24ms and the check 59ms; what fails is the
--- REPORT. Eighteen thousand eight hundred unclaimed files is not a list,
--- it is the same wall of detail the altitude work was about, one level up
--- — and a quickfix window with eighteen thousand rows is a thing you close
--- rather than a thing you work.
---
--- So the list is grouped by directory until it fits in something a reader
--- can hold: `packages/pkg042 — 100 files nothing claims` is a sentence you
--- can act on, and one hundred rows saying the same thing are not. It
--- deepens only while the result stays under the cap, so a small project
--- still gets its files named one by one.
---@param files string[]
---@param cap integer
---@return { path: string, count: integer, sample: string }[]
function M.rollup(files, cap)
  if #files <= cap then
    local out = {}
    for _, f in ipairs(files) do
      out[#out + 1] = { path = f, count = 1, sample = f }
    end
    return out
  end
  -- Deepen while it still fits. Depth 0 is the repository itself, which is
  -- the honest answer when nothing else fits: "20000 files, none claimed".
  local best
  for depth = 1, 8 do
    local groups, order = {}, {}
    for _, f in ipairs(files) do
      local parts = vim.split(f, "/", { plain = true })
      local key = table.concat(vim.list_slice(parts, 1, math.min(depth, math.max(#parts - 1, 1))), "/")
      if not groups[key] then
        groups[key] = { path = key, count = 0, sample = f }
        order[#order + 1] = groups[key]
      end
      groups[key].count = groups[key].count + 1
    end
    best = order
    if #order >= cap then
      break
    end
  end
  return best
end

--- Put the unclaimed files in the quickfix list, so the thing you do next
--- happens where every other list of work happens.
---@param opts { all: boolean }? all = every file, however many there are
function M.to_quickfix(opts)
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

  local CAP = 200
  local groups = (opts and opts.all) and M.rollup(files, math.huge) or M.rollup(files, CAP)
  local rolled = #groups < #files

  local items = {}
  for _, g in ipairs(groups) do
    items[#items + 1] = {
      filename = g.sample,
      lnum = 1,
      col = 1,
      text = g.count == 1 and "no feature claims this file"
        or ("%s — %d files, nothing claims any of them"):format(g.path, g.count),
      user_data = { scry = { unclaimed = true, count = g.count } },
    }
  end
  vim.fn.setqflist({}, " ", {
    title = ("scry: unclaimed by any feature%s"):format(rolled and " (grouped)" or ""),
    items = items,
  })
  vim.notify(
    ("[scry] %d of %d files unclaimed%s — :copen"):format(
      #files,
      total,
      rolled and (", in %d places (:ScryUnclaimed! for every file)"):format(#groups) or ""
    )
  )
end

return M
