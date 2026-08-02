-- Object recovery: drafting the features nobody has written down.
--
-- This is the one place scry lets a machine write the map, so it is worth
-- being exact about which half of the reflexion loop that is allowed to
-- touch. The whole argument for an AUTHORED model is that recovered ones are
-- about half right — architecture recovery lands near 56% accuracy, feature
-- location near half — and half right is worse than absent, because you stop
-- looking. Nothing here revises that. What it revises is the assumption that
-- authoring must start from a blank buffer.
--
-- The distinction that makes this safe is the one the whole plugin turns on:
-- a DRAFT is not a belief. A drafted feature has no ownership trail, so it
-- renders untouched, and the header counts it as untouched — which is exactly
-- the honest reading of a hundred machine-written claims nobody has read yet.
-- It is inventory. It becomes a belief when you edit it, and editing is what
-- records the trail. So the machine does the typing and you do the deciding,
-- which is the same division as everywhere else in scry.
--
-- SCOPED BY DIVERGENCE, NOT BY REPO. The worklist is the unclaimed files, so
-- a pass drafts against the gap rather than re-describing the product. That
-- keeps each pass small enough to read, which is the only thing that makes
-- "you do the deciding" true rather than aspirational, and it means the
-- report you ran to find the gap is the same report that closes it.
--
-- THE HOLDOUT IS NOT INVOLVED, and pretending otherwise would be worse than
-- saying so. A prohibition is withheld from CODE requests because a rule the
-- generator was shown proves nothing by being satisfied. This request
-- produces map text, not code, so there is no result for a leaked
-- prohibition to have been fitted to. Running assert_clean here would look
-- like a guarantee while guaranteeing nothing.
--
-- What DOES matter is that a drafting pass must not write prohibitions.
-- A never-claim lands outside the repository, unversioned, and silently
-- narrows every future cascade; one nobody read is worse than none at all.
-- The request says not to write them, and if one arrives anyway the glass
-- announces the routing on write ("N never-claims → holdout") — the same
-- notification that has always made storage routing non-silent.
--
-- THE GLASS IS THE REVIEW, not a diff tab. Conjurer's review compares two
-- versions of a source region, which is the right surface for code and the
-- wrong one for this: a drafted feature wants to be read next to the rest of
-- the map, with its claims checked against the code and its untouched marker
-- showing, and none of that survives a diff view. So the draft lands in the
-- buffer directly and the ordinary glass affordances are the review — the
-- verdicts tell you whether it described anything real, `u` discards it, and
-- nothing reaches the map file until you `:write`.
--
-- That choice is also what keeps ownership honest. Passing conjurer an
-- `on_done` is what suppresses its review tab, and it is the same hook that
-- lets scry see which claims arrived and register them as drafted, so the
-- glass watcher does not record a machine's typing as your authorship. Those
-- two are one decision, not two.
local M = {}

--- Everything that leaves scry for a drafting pass. Pure — no buffer writes,
--- no requests — so a spec can read exactly what the model is told.
---
--- Existing feature NAMES go out so a pass does not re-describe what is
--- already described. Their prose does not: unlike the code request there is
--- nothing here for prose to leak into, but it is a lot of text for no gain,
--- and the names alone answer the only question the model needs answered.
---@param map_ scry.Map
---@param unclaimed string[] Files no feature's footprint names.
---@param kindset table<string, table>? kinds in force; the draft may use no
---  others, because a kind scry cannot probe is a claim nothing can check.
---@return { lines: string[], intent: string }
function M.build(map_, unclaimed, kindset)
  local names = {}
  for _, f in ipairs(map_.features) do
    names[#names + 1] = f.name
  end

  -- The region the model rewrites. Column 0 and not `feature ...`, so every
  -- line of it is prose to the parser: if you reject the draft, or never
  -- save, what is left behind is inert.
  local lines = {
    "-- scry: drafting features for " .. #unclaimed .. " undescribed file(s).",
    "-- Reject to discard. Nothing below is a belief until you edit it.",
  }
  for _, path in ipairs(unclaimed) do
    lines[#lines + 1] = "--   " .. path
  end

  -- The vocabulary the draft is allowed. Listing it is the difference
  -- between a map of the product and a map of the filesystem: asked for
  -- "the files", a model returns eighty-six paths, which is the
  -- implementation wearing a product's clothes one rung up.
  local kindnames = {}
  for name in pairs(kindset or require("scry.kinds").BUILTIN) do
    kindnames[#kindnames + 1] = name
  end
  table.sort(kindnames)
  local kindlist = table.concat(kindnames, ", ")

  local intent = table.concat({
    "Replace this block with `feature` entries in scry's map grammar,",
    "describing what the listed files make possible. Read them.",
    "",
    "GRAMMAR (indentation is the grammar):",
    "  feature <a statement of something the user can accomplish>",
    "    two-space-indented prose: one short paragraph, what it does and why",
    "    <kind> <name>",
    "    <kind> <name>",
    "",
    "A MEMBER NAMES A TYPED OBJECT. Reach for the kinds that describe the",
    "PRODUCT before the ones that describe the code — a route or a command is",
    "something someone uses; a function is how it was built. The kinds"
      .. " available in this project, and nothing else:",
    "  " .. kindlist,
    "",
    "A member may carry its own one-line intent, indented under it: what THAT",
    "member is for, as distinct from what the feature is for.",
    "",
    "ALTITUDE is the whole point. A feature is one thing a user can",
    "accomplish in one sitting, and it must matter that they can do many of",
    "them. Not `the auth system` — that is a grouping, and it swallows the",
    "product. Not `validate the token` — that is a subfunction, which is what",
    "a claim already is. Name it the way someone using the thing would.",
    "",
    "RULES:",
    "- Every file listed above must be named by at least one claim.",
    "- Claims describe what is THERE, not what should be. Do not draft a",
    "  claim you have not read the definition for; it would render absent and",
    "  read as work nobody asked for.",
    "- Do not repeat these existing features: " .. (#names > 0 and table.concat(names, "; ") or "(none yet)"),
    "- Do not write a `never` block, or any prohibition. Those are the",
    "  reader's to decide.",
    "- Output only map text. No fences, no commentary.",
  }, "\n")

  return { lines = lines, intent = intent }
end

--- Claim ids present in `buf` right now.
---@param buf integer
---@return table<string, boolean>
local function claim_ids(buf, root)
  local mapmod = require("scry.map")
  local out = {}
  for _, c in ipairs(mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), mapmod.kinds_for(root)).claims) do
    out[mapmod.claim_id(c)] = true
  end
  return out
end

--- The drafting half, separated from the command so a spec can drive it
--- against a fake provider.
---@param root string
---@param buf integer The glass buffer.
---@param map_ scry.Map
---@param unclaimed string[]
---@return table built
function M.draft(root, buf, map_, unclaimed)
  local built = M.build(map_, unclaimed, require("scry.map").kinds_for(root))

  -- Append the region, then hand conjurer exactly those lines to rewrite.
  local first = vim.api.nvim_buf_line_count(buf)
  local insert = { "" }
  vim.list_extend(insert, built.lines)
  vim.api.nvim_buf_set_lines(buf, first, first, false, insert)
  local srow = first + 1 -- 0-based, past the blank separator

  local before = claim_ids(buf, root)

  require("conjurer.operator").conjure_region(buf, {
    kind = "line",
    srow = srow,
    erow = srow + #built.lines,
  }, built.intent, {
    note = ("scry: drafting features for %d file(s) no feature claims"):format(#unclaimed),
    -- Passing on_done is what keeps conjurer's review tab shut (see the
    -- header) and is also the only moment scry can tell a drafted claim from
    -- one you typed. It runs in the same tick as the splice, before the
    -- glass watcher's TextChanged can reach the main loop, so nothing races.
    on_done = function(err)
      if err then
        -- The placeholder block is inert prose and nothing was saved, so the
        -- honest thing is to say where it is rather than silently rearrange
        -- the buffer under a failed request.
        vim.notify("[scry] draft failed: " .. err .. " — `u` clears the block", vim.log.levels.WARN)
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local drafted = {}
      for id in pairs(claim_ids(buf, root)) do
        if not before[id] then
          drafted[#drafted + 1] = id
        end
      end
      require("scry.provenance").mark_drafted(drafted)
      vim.notify(
        ("[scry] drafted %d claim(s), all untouched — read them, edit what is right, `u` to discard"):format(
          #drafted
        )
      )
      require("scry.glass").check()
    end,
  })
  return built
end

--- Draft features for the files no feature claims.
function M.start()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  -- conjurer is a hard dependency: scry does not generate anything itself,
  -- and there is no by-hand mode to fall back to.
  if not pcall(require, "conjurer.operator") then
    error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
  end

  local mapmod = require("scry.map")
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local config = require("scry.project").resolve(state.root)
  local unclaimed, total = require("scry.divergence").unclaimed(state.root, map_, config)
  if #unclaimed == 0 then
    vim.notify(("[scry] nothing to draft — all %d files are claimed by a feature"):format(total))
    return
  end

  vim.api.nvim_buf_call(state.buf, function()
    M.draft(state.root, state.buf, map_, unclaimed)
  end)
  vim.notify(("[scry] scrying %d undescribed file(s) of %d"):format(#unclaimed, total))
end

return M
