-- Finding the tests a map is missing, from the import graph.
--
-- A test file imports the code it exercises. Reach follows imports from a
-- feature's entry points outward; this is the same graph read the other
-- way: a test-looking file whose direct imports land in a feature's
-- footprint is a candidate `exercises` claim for that feature. No model
-- call, no guessing — a file read and an intersection.
--
-- The suggestions are BUFFER EDITS, like every other machine contribution:
-- they land in the glass, `u` discards the lot, nothing reaches the map
-- file until :write. A test file the feature already claims as `module` is
-- PROMOTED — the module row goes, the exercises entry arrives — because
-- "this file exists" and "this spec passes" are different claims and the
-- second is the one a test file is for.
local M = {}

-- What counts as a test file: the FILENAME says so, never the directory.
-- Directory patterns claimed __tests__/helpers.ts as a spec — a helper the
-- runner would refuse — and every ecosystem that puts tests in a directory
-- also marks the files themselves. A test named in a way scry cannot
-- recognize is one more thing :ScryTests will not touch, and that is the
-- honest trade.
local PATTERNS = {
  "^tests?[_%-.]",
  "[_%-.]tests?%.[%w]+$",
  "^specs?[_%-.]",
  "[_%-.]specs?%.[%w]+$",
}

---@param path string repo-relative
---@return boolean
function M.looks_like_test(path)
  local base = path:match("([^/]+)$") or path
  for _, p in ipairs(PATTERNS) do
    if base:match(p) then
      return true
    end
  end
  return false
end

---@class scry.TestCandidate
---@field feature string
---@field spec string repo-relative test file
---@field promote integer? lnum of the module claim this replaces

--- Test files whose direct imports land in a feature's footprint, minus
--- the ones already claimed as exercises.
---@param root string
---@param map_ scry.Map
---@param kinds table<string, table>?
---@param files string[]? the project's source files (divergence.sources)
---@return scry.TestCandidate[]
function M.candidates(root, map_, kinds, files)
  files = files or require("scry.divergence").sources(root, require("scry.project").resolve(root))
  local imports = require("scry.imports")
  local mapmod = require("scry.map")

  -- Footprints once, minus test files themselves: a test importing a test
  -- helper says nothing about a feature.
  local footprints = {}
  for _, f in ipairs(map_.features) do
    local set = {}
    for _, path in ipairs(mapmod.footprint(f, kinds)) do
      if not M.looks_like_test(path) then
        set[path] = true
      end
    end
    footprints[f.name] = set
  end

  local out = {}
  for _, path in ipairs(files) do
    if M.looks_like_test(path) then
      local touched = imports.of(root, path)
      for _, f in ipairs(map_.features) do
        local already, module_at = false, nil
        for _, claim in ipairs(f.claims) do
          local ctarget = claim.target:match("^([^:]+)") or claim.target
          if claim.kind == "exercises" and ctarget == path then
            already = true
          elseif claim.kind == "module" and claim.target == path then
            module_at = claim.lnum
          end
        end
        if not already then
          for _, imported in ipairs(touched) do
            if footprints[f.name][imported] then
              out[#out + 1] = { feature = f.name, spec = path, promote = module_at }
              break
            end
          end
        end
      end
    end
  end
  return out
end

--- Write the candidates into the glass buffer, one undoable edit.
---@param buf integer
---@param map_ scry.Map parsed from that buffer
---@param candidates scry.TestCandidate[]
---@return integer added
function M.apply(buf, map_, candidates)
  if #candidates == 0 then
    return 0
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Per line: deletions (promoted module rows) and insertions (exercises
  -- entries at each feature's block end, under its exercises section if it
  -- already has one).
  local delete, insert_after = {}, {}

  local by_feature = {}
  for _, c in ipairs(candidates) do
    by_feature[c.feature] = by_feature[c.feature] or {}
    table.insert(by_feature[c.feature], c)
    if c.promote then
      delete[c.promote] = true
    end
  end

  for _, f in ipairs(map_.features) do
    local cands = by_feature[f.name]
    if cands then
      -- The block: header to the line before the next flush-left line.
      local h = (f.lnums or { f.lnum })[1]
      local block_end = #lines
      for i = h + 1, #lines do
        if lines[i]:match("^%S") then
          block_end = i - 1
          break
        end
      end
      while block_end > h and vim.trim(lines[block_end]) == "" do
        block_end = block_end - 1
      end
      -- An existing exercises section in this block anchors the entries;
      -- otherwise the section is opened at the block's end.
      local section = nil
      for i = h + 1, block_end do
        if lines[i]:match("^  exercises%s*$") then
          section = i
        end
      end
      local anchor = section or block_end
      if section then
        -- Past the section's existing claims, so the new ones append.
        for i = section + 1, block_end do
          if lines[i]:match("^    %S") then
            anchor = i
          else
            break
          end
        end
      end
      local rows = {}
      if not section then
        rows[#rows + 1] = "  exercises"
      end
      for _, c in ipairs(cands) do
        rows[#rows + 1] = "    " .. c.spec
      end
      insert_after[anchor] = rows
    end
  end

  local new = {}
  for i, line in ipairs(lines) do
    if not delete[i] then
      new[#new + 1] = line
    end
    if insert_after[i] then
      vim.list_extend(new, insert_after[i])
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
  return #candidates
end

--- The command: detect, write into the glass, report.
function M.start()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local kinds = mapmod.kinds_for(state.root)
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), kinds)
  local found = M.candidates(state.root, map_, kinds)
  if #found == 0 then
    vim.notify("[scry] no unclaimed tests found — every test that imports a feature's files is already an exercises claim")
    return
  end
  local promoted = 0
  for _, c in ipairs(found) do
    if c.promote then
      promoted = promoted + 1
    end
  end
  M.apply(state.buf, map_, found)
  vim.notify(
    ("[scry] %d exercises claim(s) written%s — read them, `u` discards, :w keeps; :ScryExercise runs them"):format(
      #found,
      promoted > 0 and (", %d promoted from module rows"):format(promoted) or ""
    )
  )
  glass.check()
end

return M
