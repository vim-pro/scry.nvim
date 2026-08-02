-- What a product is made of.
--
-- A feature's members used to name an EVIDENCE RELATION — `contains`,
-- `calls` — which could only ever say "go looking for this and see". So
-- every member of every feature was a file or a function, and a map of a
-- web app came out as eighty-six paths: the implementation wearing a
-- product's clothes, one rung up from the ninety-seven functions that
-- failure is named after.
--
-- A member names a typed OBJECT now. `route /checklists/[slug]` says what
-- the thing IS, and the kind carries the two things a relation never could:
-- how to find one, and — later — how to make one. A generator can write a
-- route because "route" means something; nothing can write a `contains`.
--
-- KINDS ARE PROJECT-SHAPED, which is why they are not a fixed list. The
-- archived vim.pro had six, and they were Neovim's six: `command` meant
-- nvim_create_user_command. That vocabulary describes plugins. Routes and
-- endpoints describe checklists.org. Neither list is the right one, so
-- scry ships the two that hold everywhere and a repo declares the rest in
-- .scry/config.json, where the other project-shaped facts already live.
--
-- Every kind is grounded in a probe you can read. That is the property
-- that keeps this honest: a kind is not a label someone applied, it is a
-- question with an answer on disk.
local M = {}

--- The two kinds that need no declaring.
---
--- `module` needs no parser — a file is on disk or it is not — so it holds
--- for any language, which is why it is the one kind that always works.
--- `def` needs a grammar, and says so when it does not have one.
M.BUILTIN = {
  module = { probe = "file", about = "a source file" },
  def = { probe = "definition", about = "a named definition" },
}

-- Relations, not objects. They sit in the same field as a kind because a
-- claim has one kind field, but they answer a different question — a
-- prohibition and a passing spec are not things the product is MADE of.
M.RELATION = { never = true, exercises = true }

-- Sections in the pre-kinds grammar. Kept parseable forever: a map is a
-- document someone wrote, and breaking it to tidy a vocabulary would be
-- the tool telling the author their work expired.
M.LEGACY_SECTION = { contains = true, calls = true }

--- Desugar a legacy `contains` target to the kind it always meant.
---
--- `contains` was doing two jobs the whole time and the shape said which:
--- with a symbol it asserted a definition, without one it asserted a file.
--- So this is a renaming, not a reinterpretation — no map changes meaning
--- by being read through it.
---@param target string
---@return string kind
function M.of_contains(target)
  return target:match("^.-:[%w_.]+$") and "def" or "module"
end

--- Every kind that applies to this project: the builtins, plus whatever
--- `.scry/config.json` declares.
---@param config table
---@return table<string, table>
function M.all(config)
  local out = {}
  for name, spec in pairs(M.BUILTIN) do
    out[name] = spec
  end
  for name, spec in pairs((config and config.kinds) or {}) do
    if type(spec) == "table" and not M.BUILTIN[name] and not M.RELATION[name] then
      out[name] = {
        probe = spec.path and "path" or (spec.grep and "grep" or "none"),
        path = spec.path,
        grep = spec.grep,
        about = spec.about or name,
        declared = true,
      }
    end
  end
  return out
end

--- Substitute a member's name into a probe pattern.
---
--- `{name}` is the only placeholder, and it is escaped for the probe it is
--- going into: a route named `[slug]` is brackets to ripgrep and would
--- match a character class instead of itself.
---@param pattern string
---@param name string
---@param escape "regex"|"none"
---@return string
function M.expand(pattern, name, escape)
  local value = name
  if escape == "regex" then
    value = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?{}|\\/]", "\\%0")
  end
  return (pattern:gsub("{name}", (value:gsub("%%", "%%%%"))))
end

--- Is this a kind this project knows?
---@param kind string
---@param config table
---@return boolean
function M.known(kind, config)
  return M.all(config)[kind] ~= nil
end

return M
