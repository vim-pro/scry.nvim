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
---@param examples table<string, string[]>? real names per kind, from disk
---@param def_langs string[]? languages a `def` can actually be decided in
---@return { lines: string[], intent: string }
function M.build(map_, unclaimed, kindset, examples, def_langs)
  local names = {}
  for _, f in ipairs(map_.features) do
    names[#names + 1] = f.name
  end

  -- The region the model rewrites. Column 0 and not `feature ...`, so every
  -- line of it is prose to the parser: if you reject the draft, or never
  -- save, what is left behind is inert.
  --
  -- TWO LINES, NOT SEVENTY-FOUR. The worklist used to be the region, so a
  -- draft opened by pasting every undescribed path into the buffer — a
  -- screen of file names you did not ask to read, with conjurer's narration
  -- buried at the top of it. The model needs that list; the buffer does
  -- not. It travels in the request instead, and what is left here is a
  -- place for the narration to stream into while the work happens.
  local lines = {
    "-- scry: drafting features for " .. #unclaimed .. " undescribed file(s)…",
    "-- Reject to discard. Nothing below is a belief until you edit it.",
  }

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

  -- What a name of each kind LOOKS like, shown rather than described.
  -- Told only the kind's name, a model writes what the word means to a
  -- person: `endpoint /index.json`, a URL. Scry substitutes that into
  -- `src/pages/api/{name}.ts` and reports `src/pages/api//index.json.ts`
  -- absent — accurately, about a path nobody meant. Real names settle it in
  -- one line each.
  -- `def` is only checkable where an engine can ground a definition — one
  -- language today. A def anywhere else is not wrong, it is unanswerable:
  -- it renders `– unchecked (no lua resolver)` for good, and a feature
  -- carrying two of them reads `◐ 1 of 3` forever. Say so, rather than let
  -- a drafter spend its claims on questions nothing will answer.
  local langs = table.concat(def_langs or { "lua" }, ", ")
  local defnote = ("A `def` CAN ONLY BE CHECKED IN: %s. For a file in any other language name"):format(langs)
    .. "\nthe FILE with `module`, or use a kind above — a def scry cannot check renders"
    .. "\nunchecked forever and is worth no more than saying nothing.\n"

  local shape_lines = {}
  for _, name in ipairs(kindnames) do
    local ex = (examples or {})[name]
    if ex and #ex > 0 then
      shape_lines[#shape_lines + 1] = ("  %s: %s"):format(name, table.concat(ex, ", "))
    end
  end
  shape_lines[#shape_lines + 1] = "  module: a repo-relative path, e.g. src/lib/sources.js"
  shape_lines[#shape_lines + 1] = "  def: a repo-relative path, a colon, and a symbol"
  local shapes = table.concat(shape_lines, "\n")

  local intent = table.concat({
    -- THE SNIPPET IS NOT THE TASK. conjurer frames a region as "snippet to
    -- transform", which is right for rewriting a function and wrong here:
    -- since the worklist moved into this request the region is two comment
    -- lines, and a model asked to transform two comment lines quite
    -- reasonably hands them back unchanged. It did — twice, and the second
    -- time it looked like the draft returning nothing.
    --
    -- So the instruction does not refer to the snippet at all. It says what
    -- to output, and the files it is about are in this request rather than
    -- in the buffer.
    "The snippet is a two-line placeholder. DISCARD IT.",
    "",
    "Read the files listed at the end of these instructions, then output",
    "`feature` entries in scry's map grammar describing what they make",
    "possible for someone using this product. Your entire output replaces",
    "the placeholder.",
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
    defnote,
    "A NAME IS NOT A URL. Each kind is found by a probe, and a member's name",
    "is exactly the text the probe substitutes — nothing more. Here is what",
    "names of each kind look like in THIS project, taken off disk; write",
    "names of the same shape:",
    shapes,
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
    "",
    "THE FILES, all of which must be named by at least one claim:",
    "  " .. table.concat(unclaimed, "\n  "),
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

-- THE PASS. One :ScryDraft is not one request — it is a pass over
-- everything undescribed, twelve files at a time, each batch issued when
-- the last one lands.
--
-- A batch has to be small (see BATCH) and a project has thousands of files,
-- so the two facts together mean one request can never be the unit of work.
-- Asking someone to run the command a hundred and thirty times is asking
-- them to be the loop.
--
-- It ends when the files run out, when a batch describes nothing new, when
-- a request fails, or when you say so. The no-progress rule is the one that
-- matters: without it a file the model declines to describe is asked about
-- forever.
local pass = { active = false, batches = 0, claims = 0 }

--- Stop the pass after the batch in flight.
---
--- The in-flight request is left alone rather than killed — it is already
--- paid for, and its result is a draft you can keep. :ConjureCancel is the
--- other end of that choice.
function M.stop()
  if not pass.active then
    vim.notify("[scry] no draft pass running")
    return
  end
  pass.active = false
  vim.notify("[scry] draft pass will end after the batch in flight")
end

--- Is a pass running? (For the header, and for a spec.)
---@return boolean
function M.passing()
  return pass.active
end

--- The drafting half, separated from the command so a spec can drive it
--- against a fake provider.
---@param root string
---@param buf integer The glass buffer.
---@param map_ scry.Map
---@param unclaimed string[]
---@return table built
function M.draft(root, buf, map_, unclaimed)
  -- Real names per kind, off disk, so the draft can see the shape rather
  -- than be told about it.
  local kindset = require("scry.map").kinds_for(root)
  local examples = {}
  for name, spec in pairs(kindset) do
    local ex = require("scry.kinds").examples(root, spec, 6)
    if #ex > 0 then
      examples[name] = ex
    end
  end
  -- ONE PASS IS ONE BATCH. The worklist used to go out whole, and at
  -- seventy-two files that already ran past a five-minute timeout — at
  -- twenty thousand it is not a long request, it is an impossible one.
  --
  -- A cap makes the pass finite at any size, and iterating is natural
  -- because a kept draft CLAIMS the files it described: run it again and
  -- the next batch is whatever is still undescribed. Files are taken in the
  -- order divergence found them, which groups a directory's files together,
  -- so a batch tends to be one part of the product rather than a scatter.
  -- TWELVE, NOT FORTY. Measured against the real CLI on a forty-file
  -- batch: 112 seconds of silence, then everything at once in four. The
  -- silence is the model thinking, the CLI sends no thinking text for it,
  -- and no amount of streaming can show what is not sent — so the way to
  -- see work arrive is to ask for less of it at a time. Smaller batches
  -- start producing sooner and land in waves you can read, and iterating
  -- costs nothing because a kept draft claims what it described.
  local BATCH = 12
  local batch, remaining = unclaimed, 0
  if #unclaimed > BATCH then
    batch = vim.list_slice(unclaimed, 1, BATCH)
    remaining = #unclaimed - BATCH
  end
  -- The resolver in force is what decides whether a `def` is worth writing:
  -- it is the thing that would have to check one.
  local resolver = require("scry.resolver").get(require("scry.project").resolve(root).resolver)
  local built = M.build(map_, batch, kindset, examples, resolver and resolver.def_languages)

  -- The starter is instructions for someone with no map. A draft IS a map,
  -- so the instructions go — they were telling you to run the thing you
  -- just ran, and they sat above every drafted feature until deleted by
  -- hand.
  -- A FAILED DRAFT LEAVES ITS BLOCK, by design: the notification says `u`
  -- clears it. Re-running instead of undoing then stacked a second block on
  -- the first, and a third on that — inert prose, so nothing broke, but the
  -- top of the map filled with the wreckage of attempts. Drafting clears any
  -- previous block first, since there is no reading of two of them that
  -- means anything.
  local buflines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #buflines, 1, -1 do
    if buflines[i]:match("^%-%- scry: drafting features for ") then
      local last = i
      while last < #buflines and buflines[last + 1]:match("^%-%- Reject to discard") do
        last = last + 1
      end
      vim.api.nvim_buf_set_lines(buf, i - 1, last, false, {})
      buflines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end

  local glass = require("scry.glass")
  local starter = glass.starter()
  local head = vim.api.nvim_buf_get_lines(buf, 0, #starter, false)
  if table.concat(head, "\n") == table.concat(starter, "\n") then
    vim.api.nvim_buf_set_lines(buf, 0, #starter, false, {})
  end

  -- Append the region, then hand conjurer exactly those lines to rewrite.
  local first = vim.api.nvim_buf_line_count(buf)
  local insert = { "" }
  vim.list_extend(insert, built.lines)
  vim.api.nvim_buf_set_lines(buf, first, first, false, insert)
  if remaining > 0 then
    vim.notify(
      ("[scry] drafting %d of %d undescribed files — the next %d follow when this lands (:ScryDraftStop to end)"):format(
        #batch,
        #batch + remaining,
        math.min(remaining, BATCH)
      )
    )
  end
  local srow = first + 1 -- 0-based, past the blank separator

  local before = claim_ids(buf, root)

  require("conjurer.operator").conjure_region(buf, {
    kind = "line",
    srow = srow,
    erow = srow + #built.lines,
  }, built.intent, {
    -- The worklist is repo-relative, so the drafter has to be standing at
    -- the root to read a single file of it. The glass is a scry:// buffer
    -- with no directory of its own, and nvim's cwd is wherever you opened
    -- it: from anywhere else the model got nine paths that resolve to
    -- nothing and handed the placeholder straight back.
    cwd = root,
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
        -- A failed request ends the pass. Cancelling arrives here too,
        -- which is what makes :ConjureCancel stop the whole thing and not
        -- just the batch you were looking at.
        pass.active = false
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
      -- A batch that described nothing ends the pass. Otherwise the next
      -- one is issued from what is undescribed NOW — recomputed from the
      -- buffer rather than sliced off the old list, because the draft just
      -- claimed files and may well have claimed some outside its batch.
      if pass.active then
        if #drafted == 0 then
          pass.active = false
          vim.notify(("[scry] draft pass ended: a batch described nothing new (%d claims over %d batches)"):format(
            pass.claims,
            pass.batches
          ))
        else
          pass.claims = pass.claims + #drafted
          vim.schedule(function()
            M.next_batch(root, buf)
          end)
        end
      end
    end,
  })
  return built
end

--- Issue the next batch of a pass, or finish it.
---
--- What is undescribed is recomputed from the BUFFER every time rather than
--- sliced off the list the pass started with: the last batch just claimed
--- files, and may well have claimed some that were not in it.
---@param root string
---@param buf integer
---@param begin boolean? Start a pass, rather than continue one.
function M.next_batch(root, buf, begin)
  if begin then
    pass.active, pass.batches, pass.claims = true, 0, 0
  end
  if not (pass.active and vim.api.nvim_buf_is_valid(buf)) then
    pass.active = false
    return
  end
  local mapmod = require("scry.map")
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), mapmod.kinds_for(root))
  local config = require("scry.project").resolve(root)
  local unclaimed, total = require("scry.divergence").unclaimed(root, map_, config)
  if #unclaimed == 0 then
    pass.active = false
    if pass.batches == 0 then
      vim.notify(("[scry] nothing to draft — all %d files are claimed by a feature"):format(total))
    else
      vim.notify(("[scry] draft pass done — all %d files are described (%d claims over %d batches)"):format(
        total,
        pass.claims,
        pass.batches
      ))
    end
    return
  end
  if pass.batches == 0 then
    vim.notify(("[scry] scrying %d undescribed file(s) of %d"):format(#unclaimed, total))
  end
  pass.batches = pass.batches + 1
  vim.api.nvim_buf_call(buf, function()
    M.draft(root, buf, map_, unclaimed)
  end)
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

  M.next_batch(state.root, state.buf, true)
end

return M
