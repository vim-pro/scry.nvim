-- The holdout: never-claims live OUTSIDE the repo by default, so a
-- generator that reads the project does not encounter them. Two guarantees,
-- never conflated: request-level withholding is hard (assert_clean below,
-- spec-tested); file-level invisibility holds against a repo-reading
-- generator, not against one instructed to hunt the filesystem. The cost is
-- stated plainly: out-of-repo nevers are per-machine and unversioned.
local M = {}

--- The holdout file path for a project root: config override, or
--- stdpath("state")/scry/holdout/<encoded-root>.scry (undofile-style
--- percent encoding).
---@param root string
---@param config table
---@return string
function M.path(root, config)
  if config.holdout_path and config.holdout_path ~= "" then
    local p = config.holdout_path
    if not p:match("^/") then
      p = root .. "/" .. p
    end
    return p
  end
  local dir = vim.fn.stdpath("state") .. "/scry/holdout"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(root, ":p"):gsub("[/\\:]", "%%") .. "scry"
end

--- Is the holdout stored inside the repo (weaker guarantee)?
---@param root string
---@param config table
---@return boolean
function M.in_repo(root, config)
  return M.path(root, config):sub(1, #root) == root
end

--- Write holdout lines to disk.
---@param root string
---@param config table
---@param lines string[]
function M.save(root, config, lines)
  vim.fn.writefile(lines, M.path(root, config))
end

--- Load the holdout map ({} if none).
---@param root string
---@param config table
---@return scry.Map
function M.load(root, config)
  return require("scry.map").load(M.path(root, config))
end

--- The tripwire: error if any never-pattern's raw text appears in any
--- outgoing string (intent, entry text, exemplar — everything a conjurer
--- will see). Belt-and-braces on top of construction-by-type; this is the
--- property the cascade spec nails down.
---@param strings string[]
---@param never_targets string[]
function M.assert_clean(strings, never_targets)
  for _, pattern in ipairs(never_targets) do
    for _, s in ipairs(strings) do
      if s and pattern ~= "" and s:find(pattern, 1, true) then
        error(("[scry] holdout leak: a never-pattern appears in an outgoing string (%q)"):format(pattern), 0)
      end
    end
  end
end

return M
