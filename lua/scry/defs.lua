-- Where a definition is, in whatever language it is written in.
--
-- TWO RUNGS, AND THEY ARE NOT THE SAME CLAIM.
--
--   PARSED   treesitter answered. A definition NODE by that name exists —
--            not a comment, not a string, not a mention.
--   TEXT     a line in that file looks like a definition of that name. It
--            could be inside a comment or a template literal, and this
--            cannot tell.
--
-- The parsed rung needs a grammar, and Neovim ships seven. Everything else a
-- person writes software in — TypeScript, Astro, Go, Ruby, whatever the
-- project happens to be — has no parser here unless they installed one.
--
-- Before this, `def` on anything but lua answered `– unchecked (no lua
-- resolver)` forever. Measured on a real project: an Astro/TypeScript
-- codebase where every claim scry could make topped out at "the file is on
-- disk", because the one rung above it was closed. A tool that can only
-- describe lua is a lua tool.
--
-- So the text rung exists, and it is honestly labeled. `✓ defined (text)` is
-- weaker than `✓ defined` and the wording says which one you got — the same
-- rule every label here follows.
--
-- SHIPPED QUERIES ARE ONES THAT WERE RUN. A treesitter query that has never
-- been executed against its grammar is a guess, and a wrong one produces
-- confident false verdicts rather than an error. Every entry in PARSED below
-- has a parser on the machine it was written on and a spec that runs it. A
-- language whose parser someone installs later gets the text rung until its
-- query is written and tested — worse than parsed, much better than nothing,
-- and never a lie about which it is.
local M = {}

-- Extension to treesitter language. Only what the queries below cover; a
-- miss is not an error, it is the text rung.
M.LANG = {
  lua = "lua",
  c = "c",
  h = "c",
}

-- Definition queries, per language. Probed against real code, not written
-- from the grammar docs.
M.PARSED = {
  -- 37 definitions extracted from conjurer's operator.lua.
  lua = [[
    (function_declaration name: (_) @name)
    (assignment_statement
      (variable_list name: (_) @name)
      (expression_list value: (function_definition)))
  ]],
  -- Functions by their declarator, plus types someone can claim by name.
  c = [[
    (function_definition declarator: (function_declarator declarator: (_) @name))
    (declaration declarator: (function_declarator declarator: (_) @name))
    (struct_specifier name: (type_identifier) @name)
    (enum_specifier name: (type_identifier) @name)
    (type_definition declarator: (type_identifier) @name)
  ]],
}

-- WHAT A DEFINITION LOOKS LIKE AS TEXT, across the languages people write.
--
-- Structural, not a pile of regexes. The first attempt was a list of shapes
-- like `^%s*[a-z]+%s+<symbol>` for `class Foo` — and `[a-z]+` happily matched
-- `return`, so `return renderPrintSheet(checklist)` read as a definition of
-- renderPrintSheet. A pattern list that big is not something a person can
-- audit, which is how that survived being written down.
--
-- So: find the symbol as a WHOLE WORD, then look at what sits either side of
-- it. Three things make a definition, and each is a sentence you can check.
local DECLARES = {
  -- functions
  ["function"] = true, def = true, func = true, fn = true, sub = true, proc = true, method = true,
  -- types
  class = true, interface = true, type = true, struct = true, enum = true, trait = true,
  impl = true, record = true, protocol = true, ["end"] = false,
  -- bindings
  const = true, let = true, var = true, val = true, object = true, module = true, package = true,
}

--- Does this line look like a definition of `symbol`?
---
--- Deliberately conservative. A false positive here is a `✓` on a claim
--- nothing backs, which is the one failure this whole tool exists to avoid;
--- a false negative is a `✗` on work you have done, which is visible and
--- annoying rather than dishonest.
---@param line string
---@param symbol string
---@return boolean
function M.looks_defined(line, symbol)
  local esc = symbol:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  local init = 1
  while init <= #line + 1 do
    local a, b = line:find("%f[%w_]" .. esc .. "%f[^%w_]", init)
    if not a then
      return false
    end
    init = b + 1
    local before, after = line:sub(1, a - 1), line:sub(b + 1)
    local prev_word = before:match("([%w_]+)%s*$")
    local prev_char = before:match("(%S)%s*$")

    -- 1. A DECLARING KEYWORD IMMEDIATELY BEFORE IT.
    --    `export async function loadChecklist(`, `const cache =`, `class Foo`
    if prev_word and DECLARES[prev_word:lower()] then
      return true
    end

    -- 2. IT OPENS THE LINE, and what follows opens a body or a value.
    --    `toMarkdown(checklist) {`, `onPrint: () => ...`, `SITE = "..."`
    if before:match("^%s*$") and after:match("^%s*[%(:=]") then
      return true
    end

    -- 3. IT IS A MEMBER BEING ASSIGNED.
    --    `M.request = function(config)`, `obj.render = () => ...`
    if (prev_char == "." or prev_char == ":") and after:match("^%s*=") then
      return true
    end
  end
  return false
end

--- Definitions a source file declares, parsed. nil when there is no grammar
--- for it here, or the parse failed — never an empty list, because "no
--- definitions" and "could not look" are different answers.
---@param src string
---@param lang string
---@return { name: string, lnum: integer }[]?
function M.parsed(src, lang)
  local query_text = M.PARSED[lang]
  if not query_text then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
  if not ok then
    return nil
  end
  local ok2, trees = pcall(function()
    return parser:parse()
  end)
  if not ok2 or not trees or not trees[1] then
    return nil
  end
  local ok3, query = pcall(vim.treesitter.query.parse, lang, query_text)
  if not ok3 then
    return nil
  end
  local defs = {}
  for _, node in query:iter_captures(trees[1]:root(), src, 0, -1) do
    local row = node:range()
    defs[#defs + 1] = { name = vim.treesitter.get_node_text(node, src), lnum = row + 1 }
  end
  return defs
end

--- Definitions a source file declares, by text. Always answers — that is the
--- point of it.
---@param src string
---@param symbol string
---@return { name: string, lnum: integer }[]
function M.textual(src, symbol)
  local defs = {}
  local n = 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    if M.looks_defined(line, symbol) then
      defs[#defs + 1] = { name = symbol, lnum = n }
    end
  end
  return defs
end

--- The treesitter language for a path, if one of ours covers it.
---@param path string
---@return string?
function M.lang_of(path)
  local ext = path:match("%.([%w_]+)$")
  return ext and M.LANG[ext:lower()] or nil
end

--- Which languages get the parsed rung ON THIS MACHINE. A query is only
--- worth claiming if its grammar is actually here, so this asks rather than
--- asserting — health and the drafting pass both need the true answer.
---@return string[] parsed, string[] missing
function M.available()
  local parsed, missing = {}, {}
  for lang in pairs(M.PARSED) do
    local ok = pcall(vim.treesitter.language.add, lang)
    if ok and pcall(vim.treesitter.query.parse, lang, M.PARSED[lang]) then
      parsed[#parsed + 1] = lang
    else
      missing[#missing + 1] = lang
    end
  end
  table.sort(parsed)
  table.sort(missing)
  return parsed, missing
end

return M
