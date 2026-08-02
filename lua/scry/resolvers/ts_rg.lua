-- The v0 engine: treesitter for definitions where a grammar exists, a text
-- rung for every other language, ripgrep for references and prohibitions. Every label states its fidelity — a claim
-- backed here is ACCOUNTED FOR at text/parse level, not proven correct:
--   contains ✓ defined          a named definition NODE exists in that file
--   contains ✓ defined (text)   a line there looks like a definition of it
--   contains ✓ present (file)   the file is there; nothing about its contents
--   calls    ✓ referenced (text) the token occurs; not a resolved call
--   never    ✓ no matches (rg)   no textual match; not absence of behavior
-- Scope for the text checks is the feature's derived footprint, never a
-- declared glob — see scry.map.footprint.
-- Violations carry evidence lines and ARE certain; clean is evidence only.
local M = {
  name = "ts_rg",
  -- A `def` IS ANSWERABLE IN EVERY LANGUAGE NOW. It used to be lua or
  -- nothing, which made this a lua tool: on an Astro/TypeScript project
  -- every claim it could make topped out at "the file is on disk".
  --
  -- The list is the languages that get the PARSED rung, computed rather
  -- than asserted — a query is only worth claiming if its grammar is
  -- actually on this machine. The drafting pass reads both fields.
  def_anywhere = true,
  def_languages = nil, -- set below, once scry.defs can be required
}

setmetatable(M, {
  __index = function(_, k)
    if k == "def_languages" then
      return (require("scry.defs").available())
    end
  end,
})

-- Definitions in a source file: PARSED where a grammar is here, TEXT
-- everywhere else. The line comes back with the name, because the same
-- answer has to serve the verdict AND the jump (see scry.locate) — "where"
-- can never point somewhere "✓ defined" did not mean.
---@return { name: string, lnum: integer }[]?, string fidelity
local function defs_in(path, src, symbol)
  local defs = require("scry.defs")
  local lang = defs.lang_of(path)
  local parsed = lang and defs.parsed(src, lang)
  if parsed then
    return parsed, "ts-def"
  end
  return defs.textual(src, symbol), "text-def"
end

-- Does `symbol` match a definition name exactly or as its final dot-segment
-- ("request" matches "M.request")?
local function name_matches(defs, symbol)
  return M.def_lnum(defs, symbol) ~= nil
end

--- The line a definition of `symbol` is on, or nil. Exact match, or the
--- final dot-segment ("request" matches "M.request").
---@param defs { name: string, lnum: integer }[]
---@param symbol string
---@return integer?
function M.def_lnum(defs, symbol)
  for _, d in ipairs(defs) do
    if d.name == symbol or d.name:match("%.([%w_]+)$") == symbol then
      return d.lnum
    end
  end
  return nil
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

--- Where a `contains path:symbol` claim points, for the glass to jump to.
--- Answered by the SAME query that decides the verdict, so a jump can never
--- land somewhere `✓ defined` did not mean. nil when the file is unreadable,
--- unparseable, or defines no such symbol.
---@param root string
---@param path string
---@param symbol string
---@return integer?
function M.locate(root, path, symbol)
  local src = read(root .. "/" .. path)
  if not src then
    return nil
  end
  local defs = defs_in(path, src, symbol)
  return defs and M.def_lnum(defs, symbol) or nil
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

-- Scope args for a feature's footprint. The entries are file paths derived
-- from the feature's own claims, and rg -g accepts a literal path as a
-- glob, so no translation is needed.
local function glob_args(globs)
  local args = {}
  for _, g in ipairs(globs) do
    vim.list_extend(args, { "-g", g })
  end
  return args
end

--- contains: `path:symbol` — a definition node named `symbol` in that file.
--- module: the file is on disk. No parser, so it holds for any language —
--- the one kind that always works, and the reason a map of a JavaScript
--- project is checkable at all today.
function M.check_module(ctx, claim, cb)
  local stat = vim.uv.fs_stat(ctx.root .. "/" .. claim.target)
  if stat and stat.type == "file" then
    cb({ status = "backed", fidelity = "file", label = "✓ present (file)" })
  else
    cb({ status = "missing", fidelity = "file", label = "✗ absent (no such file)" })
  end
end

--- A kind the PROJECT declared, checked by the probe it declared with.
---
--- Two probes, because two questions cover the ground: is there a file at
--- this path (`path`), and does this pattern occur anywhere in the project
--- (`grep`). A route is usually the first, an endpoint or a command the
--- second. The verdict names the probe, so nobody has to guess how strong
--- an answer they are looking at.
function M.check_kind(ctx, claim, spec, cb)
  local kinds = require("scry.kinds")
  if spec.path then
    local rel = kinds.expand(spec.path, claim.target, "none")
    local stat = vim.uv.fs_stat(ctx.root .. "/" .. rel)
    if stat and stat.type == "file" then
      cb({
        status = "backed",
        fidelity = "file",
        label = "✓ present (file)",
        evidence = { { path = rel, lnum = 1, text = rel } },
      })
    else
      cb({ status = "missing", fidelity = "file", label = ("✗ absent (no %s)"):format(rel) })
    end
    return
  end
  if spec.grep then
    local pattern = kinds.expand(spec.grep, claim.target, "regex")
    rg({ "-e", pattern }, ctx.root, function(lines, code)
      if code == 2 then
        cb({ status = "error", fidelity = "none", label = "– rg error" })
      elseif lines and #lines > 0 then
        cb({
          status = "backed",
          fidelity = "rg-text",
          label = "✓ present (text)",
          evidence = to_evidence(lines, 3),
        })
      else
        cb({ status = "missing", fidelity = "rg-text", label = "✗ absent (no match)" })
      end
    end)
    return
  end
  cb({
    status = "unchecked",
    fidelity = "none",
    label = ("– unprobed (kind %q declares no path or grep)"):format(claim.kind),
  })
end

--- def: a named definition exists in that file.
function M.check_def(ctx, claim, cb)
  local path, symbol = claim.target:match("^(.-):([%w_.]+)$")
  if not path then
    -- A `def` with no symbol is a `module` that took the wrong word. Rather
    -- than error, answer the question it plainly meant.
    return M.check_module(ctx, claim, cb)
  end
  local src = read(ctx.root .. "/" .. path)
  if not src then
    cb({ status = "missing", fidelity = "file", label = "✗ absent (no such file)" })
    return
  end
  local defs, fidelity = defs_in(path, src, symbol)
  if not defs then
    cb({ status = "unchecked", fidelity = "none", label = "– unchecked (parse failed)" })
    return
  end
  -- THE LABEL SAYS WHICH RUNG ANSWERED. `✓ defined` is a definition node;
  -- `✓ defined (text)` is a line that looks like one and could be inside a
  -- comment. Same status, different claim, and a reader must be able to tell.
  local parsed = fidelity == "ts-def"
  if name_matches(defs, symbol) then
    cb({ status = "backed", fidelity = fidelity, label = parsed and "✓ defined" or "✓ defined (text)" })
  else
    cb({
      status = "missing",
      fidelity = fidelity,
      label = parsed and "✗ absent" or "✗ absent (no definition found)",
    })
  end
end

--- calls: `[hint::]symbol` — symbol defined in files matching hint, AND
--- referenced (textually) from the feature's own files.
function M.check_calls(ctx, claim, cb)
  local hint, symbol = claim.target:match("^(.-)::([%w_.]+)$")
  if not hint then
    hint, symbol = "", claim.target
  end
  if not symbol or symbol == "" then
    cb({ status = "error", fidelity = "none", label = "– malformed target (want [hint::]symbol)" })
    return
  end

  -- Definition side: enumerate defs in the files matching the hint. EVERY
  -- language, not just lua — a `calls` claim whose definition side could only
  -- see lua reported `✗ absent` for a function that was plainly there, which
  -- is worse than not answering.
  vim.system({ "rg", "--files" }, { text = true, cwd = ctx.root }, function(out)
    vim.schedule(function()
      local files = vim.split(out.stdout or "", "\n", { plain = true, trimempty = true })
      local defined = false
      for _, f in ipairs(files) do
        if hint == "" or f:find(hint, 1, true) then
          local src = read(ctx.root .. "/" .. f)
          local defs = src and defs_in(f, src, symbol)
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
      -- Reference side: the feature's own files mention the symbol at all.
      if #ctx.globs == 0 then
        cb({
          status = "unchecked",
          fidelity = "none",
          label = "– unscoped (this feature locates nothing yet)",
        })
        return
      end
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

--- never: a verbatim rg regex with zero matches in the feature's footprint.
--- A violation is CERTAIN (evidence attached); a clean result is evidence
--- of textual absence, not proof of behavioral absence.
function M.check_never(ctx, claim, cb)
  -- No footprint means this feature locates nothing, so there is nowhere to
  -- look. Searching the whole project instead would answer a question
  -- nobody asked and report violations in files the feature does not own.
  if #ctx.globs == 0 then
    cb({
      status = "unchecked",
      fidelity = "none",
      label = "– unscoped (this feature locates nothing yet)",
    })
    return
  end
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
--- This check READS; it never runs anything. |:ScryExercise| runs and records; a
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
  -- spec's source. It is a weak check and it is labeled as one: a passing
  -- file that contains the label is NOT proof the labeled assertion ran, only
  -- that it is written down and nothing in the file failed.
  local labeled = ""
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
    labeled = "; assertion present"
  end

  local run = runs.load(ctx.root)[spec]
  if not run then
    cb({ status = "unchecked", fidelity = "none", label = "– unrun (:ScryExercise)" })
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
      label = ("✓ passing (ran %s%s)"):format(ago(run.at), labeled),
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
