-- Aiming: from what you want, to the thing it is about.
--
-- Nobody sits down wanting to look at a map. You sit down wanting to DO
-- something — add an export, fix a reload bug — and the map is how scry finds
-- the capability it belongs to. So the intent is the front door:
--
--     :Scry add a PDF export
--
-- ...puts your cursor on the capability that is about. If a feature already
-- covers it, that one. If none does, it writes one at sea level and finds
-- what it is made of (|scry-members|), so the noun is whole by the time you
-- look at it.
--
-- IT AIMS, IT DOES NOT FIRE. The cursor lands and it stops there. You see
-- the files before anything is cast across them — that is the whole shape of
-- this tool, and a step that skipped the looking would be a different
-- product.
-- What it does do is REMEMBER: `~` comes up pre-filled with the intent you
-- already gave, so agreeing costs one keystroke and disagreeing costs an
-- edit.
--
-- MATCHING IS BIASED TOWARD THE FEATURE YOU HAVE. A near-duplicate feature is
-- the failure that took one map to 301 features, and it is far cheaper to
-- widen an existing capability than to notice months later that two rows mean
-- one thing.
local M = {}

local SYSTEM = table.concat({
  "You are given something a programmer wants to do to a software product,",
  "and the list of capabilities that product is already described as having.",
  "",
  "Decide which capability the work belongs to.",
  "",
  "Answer with ONE line, in one of exactly two shapes:",
  "",
  "  MATCH: <the capability's name, copied EXACTLY>",
  "  NEW: <a name for the capability this work belongs to>",
  "",
  "Rules:",
  "- Prefer MATCH. Work that extends, fixes or changes an existing",
  "  capability belongs to it. Two names for one capability is the worst",
  "  outcome available here.",
  "- Answer NEW only when the work is a thing a person can do that the list",
  "  genuinely does not cover.",
  "- A NEW name is ONE THING A PERSON CAN DO, written the way the person",
  "  would say it, starting with a verb. Not a component, not a layer, not a",
  "  task. `Take a checklist away as a PDF`, never `PDF export module` and",
  "  never `Add PDF generation to the export handler`.",
  "- A MATCH name must be copied character for character from the list.",
  "- One line. No explanation, no punctuation around it, no code fences.",
}, "\n")

--- Everything that leaves scry to aim an intent.
---
--- Pure: no buffers, no provider, no disk.
---@param intent string
---@param map_ scry.Map
---@return { system: string, user: string }
function M.request(intent, map_)
  local out = { "WORK: " .. intent, "", "CAPABILITIES THIS PRODUCT ALREADY HAS:" }
  if #(map_.features or {}) == 0 then
    -- Said outright rather than left as an empty heading. An empty list with
    -- an instruction to "prefer MATCH" reads as a trick question.
    out[#out + 1] = "  (none — the map is empty, so the answer is NEW)"
  end
  for _, f in ipairs(map_.features or {}) do
    out[#out + 1] = "  " .. f.name
    for _, line in ipairs(f.desc or {}) do
      out[#out + 1] = "      " .. line
    end
  end
  return { system = SYSTEM, user = table.concat(out, "\n") }
end

--- Read the one line back.
---
--- A name that claims to MATCH but is not in the map is treated as NEW. The
--- model paraphrasing a feature it meant to match would otherwise move your
--- cursor to a feature that does not exist, or — worse — silently pick the
--- wrong one.
---@param result string
---@param map_ scry.Map
---@return "match"|"new"|nil kind, string? name
function M.parse(result, map_)
  for _, raw in ipairs(vim.split(result or "", "\n", { plain = true })) do
    local line = vim.trim(raw)
    local matched = line:match("^MATCH:%s*(.+)$")
    if matched then
      local name = vim.trim(matched)
      if require("scry.map").feature(map_, name) then
        return "match", name
      end
      -- Not in the map: it paraphrased. Fall through and let it be new
      -- rather than aiming at a feature nobody wrote.
      return "new", name
    end
    local fresh = line:match("^NEW:%s*(.+)$")
    if fresh then
      return "new", vim.trim(fresh)
    end
  end
  return nil, nil
end

--- Put the cursor on a feature; the plan that follows does the talking.
---@param buf integer
---@param feature scry.Feature
---@param intent string
local function land(buf, feature, intent)
  local at = (feature.lnums or { feature.lnum })[1]
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    pcall(vim.api.nvim_win_set_cursor, win, { at, 0 })
    -- The members arrive closed (|scry-mappings|); open the one you were
    -- aimed at, because its files are the thing you are here to read.
    pcall(vim.cmd, "normal! zv")
    pcall(require("scry.glass").toggle_members)
  end
  require("scry.compose").remember(intent)
end

--- Aim an intent at the capability it is about.
---@param root string
---@param buf integer the glass buffer
---@param intent string
---@param done fun(kind: string?, name: string?)? for specs
function M.at(root, buf, intent, done)
  local mapmod = require("scry.map")
  local kindset = mapmod.kinds_for(root)
  local function reparse()
    return mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), kindset)
  end
  local map_ = reparse()
  local built = M.request(intent, map_)

  local ns = vim.api.nvim_create_namespace("scry_aim")
  local function say(text)
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
        virt_text = { { "  ✨ " .. text, "ScryBuilding" } },
        virt_text_pos = "eol",
      })
    end
  end
  say(("finding what `%s` is about…"):format(intent:sub(1, 40)))

  require("conjurer").get_provider()({
    config = require("conjurer").config or {},
    system = built.system,
    user = built.user,
    intent = intent,
    cwd = root,
    timeout_ms = 120000,
  }, function(err, result)
    vim.schedule(function()
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      if err then
        vim.notify("[scry] " .. err, vim.log.levels.ERROR)
        return
      end
      local kind, name = M.parse(result, map_)
      if not name then
        vim.notify(
          ("[scry] could not tell what `%s` is about — write the feature yourself and press +"):format(intent),
          vim.log.levels.WARN
        )
        return
      end

      if kind == "match" then
        -- AIMING ENDS IN A PLAN, not a bare cursor. The cursor lands, and
        -- what this intent will do — which members change, which files get
        -- created — is written under the members where you can edit it
        -- (|scry-plan|). Firing is still yours.
        local target = mapmod.feature(map_, name)
        land(buf, target, intent)
        require("scry.plan").give(root, buf, target, intent, function()
          if done then
            done("match", name)
          end
        end)
        return
      end

      -- A NEW capability is written into the map and its members found, so
      -- the noun is whole by the time you look at it. Landing you on a bare
      -- name with nothing under it would just move the hand-typing one step
      -- along.
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Written after the last line that says anything. An empty map is one
      -- blank line, and appending past it left the first feature of a
      -- project's map on line 2 with a blank above it forever.
      local last = #lines
      while last > 0 and vim.trim(lines[last]) == "" do
        last = last - 1
      end
      local tail = {}
      if last > 0 then
        tail[#tail + 1] = ""
      end
      tail[#tail + 1] = "feature " .. name
      -- The glass opens with a blank first line (see glass.open). A map that
      -- is nothing but that line must end up blank-then-feature rather than
      -- having its one line of breathing room overwritten by the first
      -- capability anyone names.
      local from = last
      if from == 0 and #lines > 0 then
        from = 1
      end
      vim.api.nvim_buf_set_lines(buf, from, #lines, false, tail)

      local written = require("scry.map").feature(reparse(), name)
      if not written then
        vim.notify("[scry] wrote `" .. name .. "` but could not find it again", vim.log.levels.ERROR)
        return
      end
      -- A bare feature's plan IS its first members, so the plan step does
      -- both jobs here — one call, and the notes arrive intent-aware rather
      -- than describing a status quo the intent is about to change.
      land(buf, written, intent)
      require("scry.plan").give(root, buf, written, intent, function()
        if done then
          done("new", name)
        end
      end)
    end)
  end)
end

--- `:Scry {intent}` — open the glass, then aim.
---@param root string
---@param intent string
function M.start(root, intent)
  if not pcall(require, "conjurer") then
    error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
  end
  local glass = require("scry.glass")
  glass.open(root)
  local buf = glass._state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  M.at(root, buf, intent)
end

return M
