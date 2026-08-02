-- What would make these answers better, said without being asked.
--
-- Scry knows its own ceiling exactly. It knows that twelve of your claims
-- stopped at `defined (text)` because there is no TypeScript grammar here,
-- and that `✓ done` is unreachable in this project because nothing has an
-- `exercises` claim. It knew all of that and said none of it unless you
-- happened to run `:checkhealth`.
--
-- A tool that silently underperforms and waits to be interrogated about it is
-- a tool that will underperform forever. So the ceiling comes to you.
--
-- TWO KINDS OF THING, AND THEY ARE NOT HANDLED THE SAME.
--
--   CRUCIAL   scry cannot do its job without it. Not a warning — a refusal.
--             Rendering a page of `– resolver error` where prohibitions
--             should be is worse than not opening: a `never` that silently
--             stops being checked is the most dangerous state this tool has.
--
--   BETTER    the answers would be stronger. Said once, quietly, ranked by
--             how much it would actually buy IN THIS PROJECT — counted from
--             your own claims, never a generic list of features.
--
-- ONE THING AT A TIME. A list of five suggestions is a list nobody reads, and
-- the second-best suggestion is noise until the best one is done.
local M = {}

-- Extension to the treesitter language someone would install. Only what a
-- person can act on: naming a grammar that does not exist would be worse
-- than saying nothing.
local GRAMMAR = {
  ts = "typescript",
  tsx = "tsx",
  mts = "typescript",
  cts = "typescript",
  js = "javascript",
  jsx = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  astro = "astro",
  vue = "vue",
  svelte = "svelte",
  py = "python",
  go = "go",
  rb = "ruby",
  rs = "rust",
  java = "java",
  kt = "kotlin",
  swift = "swift",
  cpp = "cpp",
  cc = "cpp",
  hpp = "cpp",
  cs = "c_sharp",
  php = "php",
  ex = "elixir",
  exs = "elixir",
  scala = "scala",
  hs = "haskell",
  ml = "ocaml",
  zig = "zig",
  sh = "bash",
  bash = "bash",
  css = "css",
  scss = "scss",
  html = "html",
  json = "json",
  yaml = "yaml",
  yml = "yaml",
  sql = "sql",
}

--- What scry cannot work without.
---
--- Checked before anything opens, because the alternative is a glass full of
--- errors that reads like a broken project rather than a missing tool.
---@return string? what is missing, string? how to get it
function M.crucial()
  if vim.fn.executable("rg") ~= 1 then
    return "ripgrep (rg) is not on your PATH — prohibitions, references and "
      .. "divergence all run through it, and none of them can be checked without it",
      "brew install ripgrep   ·   https://github.com/BurntSushi/ripgrep#installation"
  end
  return nil
end

--- The one thing that would most improve this project's answers.
---
--- Ranked by what it would buy HERE, counted from the claims in front of you.
--- Nothing generic: a suggestion that does not name a number from your own
--- map is a suggestion you will learn to skip.
---@param map_ scry.Map
---@param report scry.Report?
---@param config table?
---@return { id: string, say: string, how: string }?
function M.best(map_, report, config)
  local mapmod = require("scry.map")
  local found = {}

  -- 1. GRAMMARS. Every claim that fell to the text rung is a claim that could
  -- have been grounded in a definition node.
  local capped, exts = 0, {}
  for _, claim in ipairs(map_.claims or {}) do
    local v = report and report.verdicts[mapmod.claim_id(claim)]
    if v and v.fidelity == "text-def" then
      capped = capped + 1
      local path = claim.target:match("^(.-):[%w_.]+$") or claim.target
      local ext = path:match("%.([%w_]+)$")
      local lang = ext and GRAMMAR[ext:lower()]
      if lang and not vim.tbl_contains(exts, lang) then
        exts[#exts + 1] = lang
      end
    end
  end
  if capped > 0 and #exts > 0 then
    table.sort(exts)
    local langs = table.concat(exts, " ")
    -- The instruction depends on what they already have. Telling someone to
    -- run :TSInstall when nvim-treesitter is not installed is an error
    -- message dressed as advice.
    local has_nts = pcall(require, "nvim-treesitter")
    found[#found + 1] = {
      weight = capped * 10,
      id = "grammar",
      say = ("%d claim%s stop at `defined (text)` — no grammar here for %s"):format(
        capped,
        capped == 1 and "" or "s",
        langs
      ),
      how = has_nts and (":TSInstall " .. langs)
        or ("install nvim-treesitter, then :TSInstall " .. langs),
    }
  end

  -- 2. NOTHING HAS BEEN RUN. `✓ done` is the only state that means "works",
  -- and it costs an execution. A map with no `exercises` claim has a ceiling
  -- it will never reach, and nothing on the page says so.
  local exercises, total = 0, #(map_.claims or {})
  for _, claim in ipairs(map_.claims or {}) do
    if claim.kind == "exercises" then
      exercises = exercises + 1
    end
  end
  if total > 0 and exercises == 0 then
    found[#found + 1] = {
      weight = 5,
      id = "exercises",
      say = "nothing here has been run, so no feature can reach `✓ done` — every claim is structure",
      how = "add `exercises tests/<spec>` under a feature, then :ScryExercise",
    }
  elseif exercises > 0 and not (config and config.test and config.test.cmd) then
    found[#found + 1] = {
      weight = exercises * 8,
      id = "test-cmd",
      say = ("%d exercised claim%s cannot run — no test command is configured"):format(
        exercises,
        exercises == 1 and "" or "s"
      ),
      how = "setup({ test = { cmd = { ... } } })",
    }
  end

  -- 3. THE OPERATOR ITSELF. Without conjurer there is no `~`, no `+` and no
  -- `:Scry {intent}` — which is most of the reason this buffer exists.
  if not pcall(require, "conjurer") then
    found[#found + 1] = {
      weight = 1000,
      id = "conjurer",
      say = "conjurer.nvim is not installed, so `~`, `+` and `:Scry {intent}` do nothing",
      how = "https://github.com/vim-pro/conjurer.nvim",
    }
  end

  table.sort(found, function(a, b)
    return a.weight > b.weight
  end)
  return found[1]
end

-- Said ONCE per project per session. The ceiling does not change while you
-- work, and a message that repeats on every check is a message you configure
-- away — which loses the one time it mattered.
local told = {}

--- Say the one thing, if there is one and it has not been said.
---@param root string
---@param map_ scry.Map
---@param report scry.Report?
---@param config table?
function M.offer(root, map_, report, config)
  if told[root] then
    return
  end
  local best = M.best(map_, report, config)
  if not best then
    return
  end
  told[root] = true
  -- WHERE IT WENT, because a message on the status line is gone the moment
  -- anything else prints and a reader who blinked has no way back to it. `g?`
  -- carries the same sentence for as long as they want it.
  vim.notify(("[scry] %s · %s · g? to see this again"):format(best.say, best.how), vim.log.levels.INFO)
end

--- Forget what has been said, so a spec can drive this twice.
function M.reset()
  told = {}
end

return M
