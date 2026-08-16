-- Project-local configuration.
--
-- Some of scry's config describes YOU and some describes THE REPO, and
-- until now both lived in one global `setup()`. That is fine for one
-- project and wrong for two: the right `sources` for this repo is not the
-- right one for the next, and how to run one project's specs has nothing
-- to do with how to run another's.
--
-- So the repo may carry `.scry/config.json`, and exactly five keys are
-- honored from it:
--
--   sources    which files count as claimable (divergence)
--   test       how to run ONE spec
--   resolver   which checking engine this project's languages need
--   map_path   where in the repo the map lives
--   kinds      what this product is MADE of — routes, endpoints, commands.
--              The most project-shaped fact there is: scry ships `module`
--              and `def` because they hold in every language, and every
--              kind above those describes one product and no other.
--
-- JSON rather than Lua on purpose. Executing code from a checked-out
-- repository is what Neovim gates behind 'exrc', and scry has no business
-- doing it silently for a config file.
local M = {}

-- Only these may come from the repo. Anything else in the file is ignored
-- rather than errored on: a newer scry writing a key this one does not know
-- should not break the older one.
local HONORED = { sources = true, test = true, resolver = true, map_path = true, kinds = true }

--- Read `.scry/config.json`, if any. Malformed JSON is reported once and
--- treated as absent — a broken config file must not stop you opening the
--- glass.
---@param root string
---@return table honored, string? warning
function M.load(root)
  local path = root .. "/.scry/config.json"
  local f = io.open(path, "r")
  if not f then
    return {}, nil
  end
  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return {}, ("[scry] %s is not valid JSON — ignoring it"):format(path)
  end

  local out = {}
  for key, value in pairs(decoded) do
    if HONORED[key] then
      out[key] = value
    end
  end
  return out, nil
end

--- A starter `sources` list, read off the repo itself: one glob per
--- top-level directory that has files, root-level files by name. Narrowing
--- is then DELETING LINES — the one edit nobody needs a manual for.
---@param files string[] repo-relative, from divergence.sources
---@return string[] globs
function M.sources_template(files)
  local dirs, singles, seen = {}, {}, {}
  for _, path in ipairs(files) do
    local top = path:match("^([^/]+)/")
    if top then
      if not seen[top .. "/"] then
        seen[top .. "/"] = true
        dirs[#dirs + 1] = top .. "/**"
      end
    elseif not seen[path] then
      seen[path] = true
      singles[#singles + 1] = path
    end
  end
  table.sort(dirs)
  table.sort(singles)
  vim.list_extend(dirs, singles)
  return dirs
end

--- Open `.scry/config.json` for editing — created in the buffer (not on
--- disk) when absent, pre-seeded with a `sources` list read off the repo.
--- The remedy for "too many files" is a keystroke away and lands as
--- editable text: delete the lines that are not product, then `:w`.
---@param root string
function M.edit_sources(root)
  local path = root .. "/.scry/config.json"
  vim.fn.mkdir(root .. "/.scry", "p")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if vim.fn.filereadable(path) == 1 then
    return
  end
  local files = require("scry.divergence").sources(root, M.resolve(root))
  local lines = { "{", '  "sources": [' }
  local globs = M.sources_template(files)
  for i, g in ipairs(globs) do
    lines[#lines + 1] = ('    "%s"%s'):format(g, i < #globs and "," or "")
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.notify("[scry] every line is what counts as product — delete what is not, then :w  (:h scry-project-config)")
end

--- The config that applies to `root`: your setup() with the project's own
--- keys layered on top. The project wins for the keys it owns, because it
--- knows things your vimrc cannot.
---@param root string?
---@return table
function M.resolve(root)
  local base = require("scry").config
  if not root then
    return base
  end
  local project, warning = M.load(root)
  if warning then
    vim.notify(warning, vim.log.levels.WARN)
  end
  if not next(project) then
    return base
  end
  return vim.tbl_deep_extend("force", base, project)
end

return M
