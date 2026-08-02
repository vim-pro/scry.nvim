-- Finding what a capability is made of.
--
-- Everything else in scry starts from the code. Drafting (|scry-drafting|)
-- sweeps the files nothing describes and writes features to cover them —
-- bottom-up, whole-project, and it answers "what is this repo".
--
-- This is the other direction, and it is the one you need to START work.
-- You already know the capability you want to change. You say it in your own
-- words, and scry finds what it is made of:
--
--     feature Read a checklist as markdown or JSON instead of a web page
--
-- ...is the whole thing you should ever have to type. The sentence beneath it
-- and the members under that are the answer, not the question. Typing member
-- paths by hand means knowing the layout before you are allowed to describe
-- the product, which is exactly backwards — and it was the one hand-typed
-- step left in the loop.
--
-- (This used to be called "giving the capability an address". The word was
-- decoration: every surface that speaks to a person already said "members"
-- or "files", and a coined noun that only exists in explanations is a word
-- someone has to learn for nothing. A feature is made of members; the
-- derived file set is its footprint; the cursor does the addressing, the
-- way it always has.)
--
-- WHY IT IS `+` AND NOT A NEW KEY. `+` already means "add what is not here
-- yet". On a feature with nothing under it, what is not here yet is its
-- members; anywhere else, it is features for the files nothing describes.
-- Same verb, scoped by where the cursor is.
--
-- IT SEARCHES EVERYTHING, not just the undescribed. A drafting sweep works
-- the unclaimed list because its job is coverage. This one is answering
-- "which files is THIS capability made of", and the honest answer often
-- includes files another feature already claims — one file can serve two
-- capabilities, and pretending otherwise would leave the feature short a
-- member in order to keep a count tidy.
local M = {}

local SYSTEM = table.concat({
  "You are given the name of a FEATURE — one thing a person can do with a",
  "software product — and the list of files in the project it belongs to.",
  "",
  "Say what that feature is made of.",
  "",
  "OUTPUT EXACTLY THIS SHAPE, and nothing else:",
  "",
  "  <one or two sentences saying what the feature is for>",
  "  <kind> <target>",
  "  <kind> <target>",
  "",
  "Rules:",
  "- The prose lines come first, then the member lines. No blank line.",
  "- Use ONLY the kinds listed below, and ONLY paths from the file list.",
  "- Emit no `feature` line. The feature is already named.",
  "- Every member must be a file this capability is actually made of.",
  "  A file that merely mentions it is not a member.",
  "- Three to eight members is usual. If you can only justify one, emit one.",
  "- No prose outside the shape. No fences, no commentary, no explanation.",
}, "\n")

--- Everything that leaves scry to find a feature's members.
---
--- Pure: no buffers, no provider, no disk. A spec reads every outgoing byte.
---@param name string the feature, as the user wrote it
---@param files string[] repo-relative paths the project has
---@param kindset table<string, table> the kinds in force
---@param claimed table<string, string>? path -> the feature already claiming it
---@return { system: string, user: string }
function M.request(name, files, kindset, claimed)
  local out = { "FEATURE: " .. name, "", "KINDS YOU MAY USE:" }

  local names = {}
  for kind in pairs(kindset or {}) do
    names[#names + 1] = kind
  end
  table.sort(names)
  for _, kind in ipairs(names) do
    local spec = kindset[kind]
    if type(spec) == "table" and spec.path then
      out[#out + 1] = ("  %s <name>    the file %s"):format(kind, spec.path)
    else
      out[#out + 1] = ("  %s <path>"):format(kind)
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "FILES IN THIS PROJECT:"
  for _, path in ipairs(files) do
    -- A FILE ANOTHER FEATURE CLAIMS IS STILL FAIR GAME, and it is labeled
    -- rather than hidden. One file can serve two capabilities; withholding
    -- it would silently leave this feature short a member. Saying who else claims it
    -- is what lets the answer notice it is describing something already
    -- described, which is the failure that fragments a map.
    local owner = claimed and claimed[path]
    out[#out + 1] = owner and ("  %s   (already part of: %s)"):format(path, owner) or ("  %s"):format(path)
  end

  return { system = SYSTEM, user = table.concat(out, "\n") }
end

--- Read an answer into the lines that go under a feature.
---
--- Tolerant of the model's habits and strict about the grammar: a line is
--- kept as a MEMBER only when its first word is a kind this project knows,
--- which is the same test map.parse makes. Anything else is prose, and prose
--- is never checked — so a wrong guess here costs a sentence, not a claim.
---@param result string
---@param kindset table<string, table>
---@return string[] lines, integer members
function M.parse(result, kindset)
  local desc, members = {}, {}
  for _, raw in ipairs(vim.split(result or "", "\n", { plain = true })) do
    local line = vim.trim(raw)
    -- Fences, and the shape's own placeholders — which a model sometimes
    -- echoes back rather than filling in. A placeholder line is one that is
    -- NOTHING BUT `<...>` tokens; `<kind> <target>` is two of them, so a
    -- whole-line test for a single one missed it and it landed in the map as
    -- the feature's description.
    local bare = line:gsub("<[%a_]+>", ""):gsub("%s", "")
    if line ~= "" and not line:match("^```") and not (line:find("<") and bare == "") then
      local kind, target = line:match("^([%w_]+)%s+(%S.*)$")
      if kind and kindset[kind] then
        members[#members + 1] = "  " .. kind .. " " .. vim.trim(target)
      elseif #members == 0 then
        -- Prose only BEFORE the first member. A sentence after them is the
        -- model explaining itself, and explanation is not description.
        desc[#desc + 1] = "  " .. line
      end
    end
  end
  local lines = {}
  vim.list_extend(lines, desc)
  vim.list_extend(lines, members)
  return lines, #members
end

--- Does this feature still need its members found?
---
--- A feature that has members does not. This deliberately does NOT ask
--- whether they hold: a member pointing at a file that does not exist yet is
--- work you described on purpose (|scry-compose|), and running `+` again on
--- it would delete the thing you were about to build.
---@param feature scry.Feature
---@return boolean
function M.wanted(feature)
  return #feature.claims == 0
end

--- Fill in the feature under the cursor.
---@param root string
---@param buf integer the glass buffer
---@param feature scry.Feature
---@param done fun(members: integer)? for specs
function M.give(root, buf, feature, done)
  local mapmod = require("scry.map")
  local kindset = mapmod.kinds_for(root)
  local config = require("scry.project").resolve(root)
  local files = require("scry.divergence").sources(root, config)
  if #files == 0 then
    vim.notify("[scry] no files found to search for members", vim.log.levels.WARN)
    return
  end

  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), kindset)
  local claimed = {}
  for _, f in ipairs(map_.features) do
    for _, path in ipairs(mapmod.footprint(f, kindset)) do
      claimed[path] = f.name
    end
  end

  local built = M.request(feature.name, files, kindset, claimed)

  local ns = vim.api.nvim_create_namespace("scry_members")
  local at = (feature.lnums or { feature.lnum })[1] - 1
  local started = vim.uv.hrtime()
  local function say(text)
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, at, 0, {
        virt_text = { { "  ✨ " .. text, "ScryBuilding" } },
        virt_text_pos = "eol",
      })
    end
  end
  say(("looking through %d files…"):format(#files))

  require("conjurer").get_provider()({
    config = require("conjurer").config or {},
    system = built.system,
    user = built.user,
    intent = "find files for " .. feature.name,
    cwd = root,
    timeout_ms = 300000,
    on_narrate = function(line)
      say(("%s  %ds"):format(line:sub(1, 60), math.floor((vim.uv.hrtime() - started) / 1e9)))
    end,
  }, function(err, result)
    vim.schedule(function()
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      if err then
        vim.notify("[scry] " .. feature.name .. ": " .. err, vim.log.levels.ERROR)
        return
      end
      local lines, members = M.parse(result, kindset)
      if members == 0 then
        vim.notify(
          ("[scry] found nothing `%s` could be made of — say it differently, or name a member yourself"):format(
            feature.name
          ),
          vim.log.levels.WARN
        )
        return
      end
      -- Inserted right under the feature's own line, which is where the
      -- grammar puts them and where the cursor already is. An ordinary
      -- buffer edit, so `u` takes it back like anything else you typed.
      vim.api.nvim_buf_set_lines(buf, at + 1, at + 1, false, lines)
      vim.notify(("[scry] %d member%s · u to undo"):format(members, members == 1 and "" or "s"))
      require("scry.glass").check()
      if done then
        done(members)
      end
    end)
  end)
end

--- `+` on a feature that has no members yet.
---@return boolean handled
function M.at_cursor()
  local compose = require("scry.compose")
  local feature, state = compose.at_cursor()
  if not (feature and state.root and state.buf) then
    return false
  end
  if not M.wanted(feature) then
    return false
  end
  if not pcall(require, "conjurer") then
    error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
  end
  M.give(state.root, state.buf, feature)
  return true
end

return M
