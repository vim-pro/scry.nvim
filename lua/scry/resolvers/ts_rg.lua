-- The v0 engine: treesitter for definitions (lua only), ripgrep for
-- references and prohibitions. Every label states its fidelity — a claim
-- backed here is ACCOUNTED FOR at text/parse level, not proven correct:
--   contains ✓ defined          a named definition node exists in that file
--   calls    ✓ referenced (text) the token occurs; not a resolved call
--   never    ✓ no matches (rg)   no textual match; not absence of behavior
-- Violations carry evidence lines and ARE certain; clean is evidence only.
local M = {
  name = "ts_rg",
}

-- Definitions a lua file declares: function_declaration names plus
-- `X = function(...)` assignments. (The query probed against real code:
-- 37 definitions extracted from conjurer's operator.lua.)
local DEF_QUERY = [[
  (function_declaration name: (_) @name)
  (assignment_statement
    (variable_list name: (_) @name)
    (expression_list value: (function_definition)))
]]

-- Extract definition names from lua source text.
---@return string[]?
local function lua_defs(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "lua")
  if not ok then
    return nil
  end
  local ok2, trees = pcall(function()
    return parser:parse()
  end)
  if not ok2 or not trees or not trees[1] then
    return nil
  end
  local query = vim.treesitter.query.parse("lua", DEF_QUERY)
  local names = {}
  for _, node in query:iter_captures(trees[1]:root(), src, 0, -1) do
    names[#names + 1] = vim.treesitter.get_node_text(node, src)
  end
  return names
end

-- Does `symbol` match a definition name exactly or as its final dot-segment
-- ("request" matches "M.request")?
local function name_matches(defs, symbol)
  for _, d in ipairs(defs) do
    if d == symbol or d:match("%.([%w_]+)$") == symbol then
      return true
    end
  end
  return false
end

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Human age of a timestamp. Dynamic evidence must never render without one:
-- the age is the difference between "this passes" and "this passed once".
local function ago(at)
  local secs = os.time() - (at or 0)
  if secs < 60 then
    return secs .. "s ago"
  elseif secs < 3600 then
    return math.floor(secs / 60) .. "m ago"
  elseif secs < 86400 then
    return math.floor(secs / 3600) .. "h ago"
  end
  return math.floor(secs / 86400) .. "d ago"
end

-- Failure output as evidence lines, so a failing claim carries the reason the
-- way a violated prohibition carries its match.
local function tail_evidence(spec, output)
  local ev = {}
  for _, line in ipairs(output or {}) do
    if vim.trim(line) ~= "" then
      ev[#ev + 1] = { path = spec, lnum = 0, text = vim.trim(line) }
    end
  end
  return ev
end

-- Run rg asynchronously; cb(lines|nil, code). Lines are "path:lnum:text".
local function rg(args, cwd, cb)
  vim.system(vim.list_extend({ "rg", "-n", "--no-heading" }, args), { text = true, cwd = cwd }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        local lines = vim.split(out.stdout or "", "\n", { plain = true, trimempty = true })
        cb(lines, 0)
      else
        cb(nil, out.code) -- 1 = no matches, 2 = error
      end
    end)
  end)
end

local function to_evidence(lines, limit)
  local ev = {}
  for i = 1, math.min(#lines, limit or 5) do
    local path, lnum, text = lines[i]:match("^(.-):(%d+):(.*)$")
    if path then
      ev[#ev + 1] = { path = path, lnum = tonumber(lnum), text = vim.trim(text) }
    end
  end
  return ev
end

-- Glob args for a concern's files.
local function glob_args(globs)
  local args = {}
  for _, g in ipairs(globs) do
    vim.list_extend(args, { "-g", g })
  end
  return args
end

--- contains: `path:symbol` — a definition node named `symbol` in that file.
function M.check_contains(ctx, claim, cb)
  local path, symbol = claim.target:match("^(.-):([%w_.]+)$")
  if not path then
    cb({ status = "error", fidelity = "none", label = "– malformed target (want path:symbol)" })
    return
  end
  if not path:match("%.lua$") then
    cb({ status = "unchecked", fidelity = "none", label = "– unchecked (no lua resolver)" })
    return
  end
  local src = read(ctx.root .. "/" .. path)
  if not src then
    cb({ status = "missing", fidelity = "ts-def", label = "✗ absent (no such file)" })
    return
  end
  local defs = lua_defs(src)
  if not defs then
    cb({ status = "unchecked", fidelity = "none", label = "– unchecked (parse failed)" })
    return
  end
  if name_matches(defs, symbol) then
    cb({ status = "backed", fidelity = "ts-def", label = "✓ defined" })
  else
    cb({ status = "missing", fidelity = "ts-def", label = "✗ absent" })
  end
end

--- calls: `[hint::]symbol` — symbol defined in files matching hint, AND
--- referenced (textually) from the concern's files.
function M.check_calls(ctx, claim, cb)
  local hint, symbol = claim.target:match("^(.-)::([%w_.]+)$")
  if not hint then
    hint, symbol = "", claim.target
  end
  if not symbol or symbol == "" then
    cb({ status = "error", fidelity = "none", label = "– malformed target (want [hint::]symbol)" })
    return
  end

  -- Definition side: enumerate defs in lua files matching the hint.
  vim.system({ "rg", "--files", "-g", "*.lua" }, { text = true, cwd = ctx.root }, function(out)
    vim.schedule(function()
      local files = vim.split(out.stdout or "", "\n", { plain = true, trimempty = true })
      local defined = false
      for _, f in ipairs(files) do
        if hint == "" or f:find(hint, 1, true) then
          local src = read(ctx.root .. "/" .. f)
          local defs = src and lua_defs(src)
          if defs and name_matches(defs, symbol) then
            defined = true
            break
          end
        end
      end
      if not defined then
        cb({ status = "missing", fidelity = "ts-def", label = "✗ absent" })
        return
      end
      -- Reference side: the concern's files mention the symbol at all.
      local args = vim.list_extend({ "--word-regexp", "-F", symbol }, glob_args(ctx.globs))
      rg(args, ctx.root, function(lines, code)
        if code == 2 then
          cb({ status = "error", fidelity = "none", label = "– rg error" })
        elseif lines and #lines > 0 then
          cb({
            status = "backed",
            fidelity = "rg-text",
            label = "✓ referenced (text)",
            evidence = to_evidence(lines, 3),
          })
        else
          cb({ status = "missing", fidelity = "rg-text", label = "✗ unreferenced" })
        end
      end)
    end)
  end)
end

--- never: a verbatim rg regex with zero matches in the concern's files.
--- A violation is CERTAIN (evidence attached); a clean result is evidence
--- of textual absence, not proof of behavioral absence.
function M.check_never(ctx, claim, cb)
  local args = vim.list_extend({ "-e", claim.target }, glob_args(ctx.globs))
  rg(args, ctx.root, function(lines, code)
    if code == 2 then
      cb({ status = "error", fidelity = "none", label = "– rg error (bad pattern?)" })
    elseif lines and #lines > 0 then
      cb({ status = "violated", fidelity = "rg-text", label = "✗ VIOLATED", evidence = to_evidence(lines, 5) })
    else
      cb({ status = "clean", fidelity = "rg-text", label = "✓ no matches (rg)" })
    end
  end)
end

--- exercises: `path` or `path:assertion label`.
---
--- This check READS; it never runs anything. |:ScryRun| runs and records; a
--- check reports what the last run left, and only while nothing it depended
--- on has moved since. A stale pass is reported as unchecked rather than as
--- a pass, because it is the one verdict whose staleness is invisible: the
--- file still says "passing" long after the code stopped agreeing.
function M.check_exercises(ctx, claim, cb)
  local runs = require("scry.runs")
  local spec, label = claim.target:match("^([^:]+):(.+)$")
  spec = spec or claim.target

  if not read(ctx.root .. "/" .. spec) then
    cb({ status = "missing", fidelity = "none", label = "✗ absent — no such spec file" })
    return
  end

  -- If the claim names an assertion, that name must actually appear in the
  -- spec's source. It is a weak check and it is labelled as one: a passing
  -- file that contains the label is NOT proof the labelled assertion ran, only
  -- that it is written down and nothing in the file failed.
  local labelled = ""
  if label then
    local src = read(ctx.root .. "/" .. spec)
    if not (src and src:find(label, 1, true)) then
      cb({
        status = "missing",
        fidelity = "ts-def",
        label = "✗ absent — the spec has no assertion by that name",
      })
      return
    end
    labelled = "; assertion present"
  end

  local run = runs.load(ctx.root)[spec]
  if not run then
    cb({ status = "unchecked", fidelity = "none", label = "– unrun (:ScryRun)" })
    return
  end

  local deps = runs.scope(ctx.root, ctx.globs)
  deps[#deps + 1] = spec
  if runs.stale(run, ctx.root, deps) then
    cb({
      status = "unchecked",
      fidelity = "none",
      label = ("– stale (code changed since the run %s)"):format(ago(run.at)),
    })
    return
  end

  if run.ok then
    cb({
      status = "backed",
      fidelity = "run",
      label = ("✓ passing (ran %s%s)"):format(ago(run.at), labelled),
    })
  else
    cb({
      status = "violated",
      fidelity = "run",
      label = ("✗ FAILING (ran %s)"):format(ago(run.at)),
      evidence = tail_evidence(spec, run.output),
    })
  end
end

return M
