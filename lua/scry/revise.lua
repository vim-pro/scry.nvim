-- A project-wide intent, cast across the map itself.
--
-- `:Scry {intent}` aims at ONE capability. Some intents are about the whole
-- pane — split a group, rename a concept everywhere, describe what is
-- missing — and the pane is a buffer, so the verb is the one the glass
-- already has: `~` away from any feature sends the ENTIRE map out with your
-- sentence and splices the revised map back as one undoable edit.
--
-- THE GLASS IS THE REVIEW, exactly as it is for drafting: the result is
-- text under your cursor, every claim it makes is checked the moment it
-- lands, `u` takes the whole revision back, and nothing reaches the map
-- file until :write. New members that do not exist yet arrive reading
-- `✗ absent` — which is the revised map handing you its own worklist.
local M = {}

--- The packed intent for a whole-map cast. Pure, so a spec reads every
--- outgoing byte.
---@param intent string what the person asked for
---@param kindset table<string, table>
---@param examples table<string, string[]> real names per kind, off disk
---@param def_langs string[]?
---@param unclaimed string[] files no feature claims yet
---@return string
function M.build(intent, kindset, examples, def_langs, unclaimed)
  local kindnames = {}
  for name in pairs(kindset or require("scry.kinds").BUILTIN) do
    kindnames[#kindnames + 1] = name
  end
  table.sort(kindnames)

  local shapes = {}
  for _, name in ipairs(kindnames) do
    local ex = (examples or {})[name]
    if ex and #ex > 0 then
      shapes[#shapes + 1] = ("  %s: %s"):format(name, table.concat(ex, ", "))
    end
  end
  shapes[#shapes + 1] = "  module: a repo-relative path"
  shapes[#shapes + 1] = "  def: a repo-relative path, a colon, and a symbol"

  local langs = table.concat(def_langs or {}, ", ")

  return table.concat({
    "The snippet is this project's ENTIRE feature map. Carry out the intent",
    "on it and output the complete revised map — your whole output replaces",
    "the snippet, so anything you leave out is deleted.",
    "",
    "INTENT:",
    "  " .. intent,
    "",
    "GRAMMAR (indentation is the grammar):",
    "  a flush-left line of plain words   a heading — one level of grouping",
    "  feature <what a user can do>       a feature; prose indented two",
    "  spaces under it; members too. `never` and `exercises` open sections",
    "  whose claims are indented four. One blank line between features;",
    "  prose stays indented even when it wraps.",
    "",
    "The kinds available in this project, and nothing else:",
    "  " .. table.concat(kindnames, ", "),
    "What names of each kind look like here, taken off disk:",
    table.concat(shapes, "\n"),
    #langs > 0 and ("A `def` is grounded by a parser for: %s — elsewhere by text."):format(langs)
      or "A `def` is checked textually here.",
    "",
    "RULES:",
    "- Touch ONLY what the intent requires. Everything else is someone's",
    "  work and comes back byte-for-byte, prose and blank lines included.",
    "- Never drop a `never` or `exercises` claim unless the intent says to.",
    "- A member you write must describe what is THERE, or be work the",
    "  intent is asking for — it will render ✗ absent until built, which",
    "  is correct.",
    "- Features sit at user level: one thing a person can accomplish. A",
    "  heading is a few plain words, not a feature.",
    "- Output only map text. No fences, no commentary.",
    "",
    "FILES NO FEATURE CLAIMS YET, if the intent needs ground to describe:",
    "  " .. (#(unclaimed or {}) > 0 and table.concat(unclaimed, "\n  ") or "(none)"),
  }, "\n")
end

--- `~` away from a feature: revise the whole map toward an intent.
function M.start()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  if not pcall(require, "conjurer") then
    error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
  end

  vim.ui.input({ prompt = "Conjure the map: " }, function(intent)
    if not intent or vim.trim(intent) == "" then
      return
    end
    local mapmod = require("scry.map")
    local kindset = mapmod.kinds_for(state.root)
    local examples = {}
    for name, spec in pairs(kindset) do
      local ex = require("scry.kinds").examples(state.root, spec, 6)
      if #ex > 0 then
        examples[name] = ex
      end
    end
    local config = require("scry.project").resolve(state.root)
    local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), kindset)
    local before = #map_.features
    local ok_div, unclaimed = pcall(function()
      return require("scry.divergence").unclaimed(state.root, map_, config)
    end)
    local resolver = require("scry.resolver").get(config.resolver ~= "" and config.resolver or nil)
    local built = M.build(vim.trim(intent), kindset, examples, resolver and resolver.def_languages, ok_div and unclaimed or {})

    require("conjurer.operator").conjure_region(state.buf, {
      kind = "line",
      srow = 0,
      erow = vim.api.nvim_buf_line_count(state.buf),
    }, built, {
      cwd = state.root,
      timeout_ms = 900000,
      label = ("revising the map: %s"):format(intent:sub(1, 50)),
      note = "scry: revising the whole map",
      -- on_done keeps conjurer's review tab shut: the glass IS the review —
      -- the verdicts audit the revision the moment it lands, and `u` is the
      -- rejection.
      on_done = function(err)
        if err then
          vim.notify("[scry] map revision failed: " .. err, vim.log.levels.WARN)
          return
        end
        if not vim.api.nvim_buf_is_valid(state.buf) then
          return
        end
        local now = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), kindset)
        if before > 0 and #now.features == 0 then
          -- The model returned something that parses to nothing — prose,
          -- an apology, an empty page. Say so loudly; `u` is one keystroke.
          vim.notify("[scry] the revision emptied the map — `u` takes it back", vim.log.levels.ERROR)
        else
          vim.notify(
            ("[scry] map revised (%d → %d features) — read it, `u` discards, :w keeps"):format(before, #now.features)
          )
        end
        glass.check()
      end,
    })
  end)
end

return M
