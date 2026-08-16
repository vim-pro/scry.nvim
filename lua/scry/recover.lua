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
-- a DRAFT is not a belief. It arrives as ordinary buffer text — claims
-- checked like any other, verdicts saying whether it described anything real
-- — and nothing reaches the map file until you :write. Reading and editing
-- it is the review. So the machine does the typing and you do the deciding,
-- which is the same division as everywhere else in scry.
--
-- SCOPED BY DIVERGENCE, NOT BY REPO. The worklist is the unclaimed files, so
-- a pass drafts against the gap rather than re-describing the product. That
-- keeps each pass small enough to read, which is the only thing that makes
-- "you do the deciding" true rather than aspirational, and it means the
-- report you ran to find the gap is the same report that closes it.
--
-- A DRAFTING PASS MUST NOT WRITE PROHIBITIONS. A rule is something a person
-- chooses to impose; a machine-invented one silently narrows every future
-- cast, and one nobody chose is worse than none at all. The request says
-- not to write them, and if one arrives anyway it lands as ordinary map
-- text under your eyes, where deleting it is `dd`.
--
-- THE GLASS IS THE REVIEW, not a diff tab. Conjurer's review compares two
-- versions of a source region, which is the right surface for code and the
-- wrong one for this: a drafted feature wants to be read next to the rest of
-- the map, with its claims checked against the code and its verdicts
-- showing, and none of that survives a diff view. So the draft lands in the
-- buffer directly and the ordinary glass affordances are the review — the
-- verdicts tell you whether it described anything real, `u` discards it, and
-- nothing reaches the map file until you `:write`.
--
-- Passing conjurer an `on_done` is what suppresses its review tab, and it is
-- the same hook that lets scry count which claims a batch added — the number
-- the pass's progress guard watches.
local M = {}

-- TWELVE, NOT FORTY. Measured against the real CLI on a forty-file batch:
-- 112 seconds of silence, then everything at once in four. The silence is
-- the model thinking, the CLI sends no thinking text for it, and no amount
-- of streaming can show what is not sent — so the way to see work arrive
-- is to ask for less of it at a time.
local BATCH = 12

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
---@param survey boolean? one high-level pass over the whole worklist:
---  few sea-level features, coarse claims, judged from paths — the right
---  first contact with a repo too big to read file by file.
function M.build(map_, unclaimed, kindset, examples, def_langs, survey)
  -- WHAT IS ALREADY DESCRIBED, so a batch can add to it instead of
  -- inventing alongside it. The most recent come first: a pass works
  -- through a project in divergence's order, so the features written last
  -- are the ones nearest the files being described now.
  --
  -- Capped, and the cap is stated rather than applied quietly — a list that
  -- grew with the map put three hundred names in every request.
  local SHOWN = 40
  local names, shown = {}, 0
  for i = #map_.features, 1, -1 do
    if shown >= SHOWN then
      break
    end
    shown = shown + 1
    names[#names + 1] = map_.features[i].name
  end
  local more = #map_.features - #names

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
    survey and ("-- scry: surveying " .. #unclaimed .. " undescribed file(s) at high level…")
      or ("-- scry: drafting features for " .. #unclaimed .. " undescribed file(s)…"),
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
  -- A `def` IS ANSWERABLE EVERYWHERE now, at one of two rungs: parsed where
  -- a grammar is installed, textual otherwise. It used to be lua or nothing,
  -- which meant a drafter working an Astro project had no honest claim
  -- stronger than "this file exists" and spent every def on a question that
  -- rendered `– unchecked` forever.
  local langs = table.concat(def_langs or {}, ", ")
  local defnote = "A `def path:symbol` is checked in EVERY language. Where a treesitter grammar\n"
    .. (#langs > 0 and ("is installed (%s) it is grounded in a definition node; elsewhere a line\n"):format(langs) or "is installed it is grounded in a definition node; elsewhere a line\n")
    .. "that looks like a definition is enough, and the verdict says which it was.\n"
    .. "Prefer a real symbol over naming the bare FILE with `module`: a file path says\n"
    .. "only that something is there.\n"

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
    "  (one blank line between features; prose lines stay two-space indented,",
    "   never flush left, even when they wrap)",
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
    survey and table.concat({
      "- This is a FIRST, HIGH-LEVEL pass over the whole project. Write the",
      "  FEW features — five to fifteen — that say what this product does at",
      "  user level. Breadth over depth.",
      "- Group them: a flush-left line of a few plain words above each group",
      "  of related features, three to six groups, a blank line around it.",
      "  A heading is prose, not a feature — no `feature` keyword.",
      "- Judge from the paths and names. Read a file only when its path",
      "  leaves you genuinely unsure; do NOT read every file.",
      "- Claim files coarsely: `module <path>` (or a kind member) under the",
      "  feature each file serves. Do not write `def` claims in this pass —",
      "  a definition you have not read renders absent.",
      "- Every file listed above must be named by at least one claim.",
    }, "\n") or table.concat({
      "- Every file listed above must be named by at least one claim.",
      "- Claims describe what is THERE, not what should be. Do not draft a",
      "  claim you have not read the definition for; it would render absent and",
      "  read as work nobody asked for.",
      "- A feature is something a PERSON CAN DO, not a file. One feature",
      "  usually takes several files. Do not write a feature per file.",
    }, "\n"),
    "- These features already exist" .. (more > 0 and (" (%d most recent of %d)"):format(#names, #map_.features) or "") .. ":",
    (#names > 0 and ("    " .. table.concat(names, "\n    ")) or "    (none yet)"),
    "- If a file serves one of them, ADD TO IT: write that feature's name",
    "  again, exactly, with only the new member under it. Re-opening a",
    "  feature is how a map grows. Do not restate its existing members.",
    "- Only write a NEW feature for something none of the above covers. A",
    "  different wording of the same capability is not a new feature — it is",
    "  the same one, and belongs under the name already written.",
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

-- THE PASS. One `+` is not one request — it is a pass over
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
local pass = { active = false, batches = 0, claims = 0, unclaimed = nil }

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

-- A FRESH REPO IS A BIG ASK. On a project where thousands of files are
-- undescribed, a full pass is hundreds of model calls — hours, not a
-- moment — and the most likely first `+` on a day-one repo is exploratory.
-- So scale is stated before it is spent: past five batches' worth, the
-- first press says the size and the remedy, and pressing again inside a
-- minute means you meant it.
local armed = nil
local ARM_BATCHES, ARM_SECONDS = 5, 60

--- Should a pass over `n` undescribed files start, or say its size first?
---@param n integer files on the worklist
---@param now integer? os.time(), injectable for specs
---@return string? warning nil means proceed
function M.gate(n, now)
  now = now or os.time()
  if n <= BATCH * ARM_BATCHES then
    armed = nil
    return nil
  end
  if armed and now - armed < ARM_SECONDS then
    armed = nil
    return nil
  end
  armed = now
  return ("[scry] %d files are undescribed. + again drafts a HIGH-LEVEL first pass — one request, a handful of sea-level features over all of them. If many of these are not really the product (vendored, generated, fixtures), :ScrySources first: it opens the list of what counts, and you delete lines."):format(
    n
  )
end

--- The drafting half, separated from the command so a spec can drive it
--- against a fake provider.
---@param root string
---@param buf integer The glass buffer.
---@param map_ scry.Map
---@param unclaimed string[]
---@return table built
function M.draft(root, buf, map_, unclaimed, survey)
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
  -- Smaller batches start producing sooner and land in waves you can read
  -- (see BATCH above).
  -- A SURVEY TAKES THE WHOLE LIST. Its request carries paths, not file
  -- contents, and its instructions say not to read them — so the size that
  -- made a whole-list batch impossible does not apply.
  local batch, remaining = unclaimed, 0
  if not survey and #unclaimed > BATCH then
    batch = vim.list_slice(unclaimed, 1, BATCH)
    remaining = #unclaimed - BATCH
  end
  -- The resolver in force is what decides whether a `def` is worth writing:
  -- it is the thing that would have to check one.
  local resolver = require("scry.resolver").get(require("scry.project").resolve(root).resolver)
  local built = M.build(map_, batch, kindset, examples, resolver and resolver.def_languages, survey)

  -- A FAILED DRAFT LEAVES ITS BLOCK, by design: the notification says `u`
  -- clears it. Re-running instead of undoing then stacked a second block on
  -- the first, and a third on that — inert prose, so nothing broke, but the
  -- top of the map filled with the wreckage of attempts. Drafting clears any
  -- previous block first, since there is no reading of two of them that
  -- means anything.
  local buflines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #buflines, 1, -1 do
    if buflines[i]:match("^%-%- scry: drafting features for ") or buflines[i]:match("^%-%- scry: surveying ") then
      local last = i
      while last < #buflines and buflines[last + 1]:match("^%-%- Reject to discard") do
        last = last + 1
      end
      vim.api.nvim_buf_set_lines(buf, i - 1, last, false, {})
      buflines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end

  -- Append the region, then hand conjurer exactly those lines to rewrite.
  local first = vim.api.nvim_buf_line_count(buf)
  local insert = { "" }
  vim.list_extend(insert, built.lines)
  vim.api.nvim_buf_set_lines(buf, first, first, false, insert)
  if remaining > 0 then
    vim.notify(
      ("[scry] drafting %d of %d undescribed files — the next %d follow when this lands (+ to stop)"):format(
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
    -- MEASURED, not guessed. Twelve files came back in 51s, 55s, 84s, 89s
    -- and 265s across real runs — the spread is the model's, not the
    -- batch's, and conjurer's 300s default sits inside it. A pass that dies
    -- five minutes in has cost you the wait and given you nothing, so the
    -- ceiling here is loose enough that only a genuinely stuck request
    -- reaches it.
    timeout_ms = 900000,
    -- The status line shows the intent's first line unless told otherwise,
    -- and the drafting request opens by telling the model to discard the
    -- placeholder — which read, on screen, as scry conjuring a sentence
    -- about a placeholder. What a person wants to know is which files and
    -- how far along the pass is.
    label = survey and ("surveying %d undescribed files at high level"):format(#batch)
      or ("drafting %d of %d undescribed files (batch %d)"):format(#batch, #batch + remaining, pass.batches),
    note = ("scry: drafting features for %d file(s) no feature claims"):format(#unclaimed),
    -- Passing on_done is what keeps conjurer's review tab shut (see the
    -- header) and is also the moment scry can count what the batch added.
    -- It runs in the same tick as the splice, before the glass watcher's
    -- TextChanged can reach the main loop, so nothing races.
    on_done = function(err)
      if err then
        -- The placeholder block is inert prose and nothing was saved, so the
        -- honest thing is to say where it is rather than silently rearrange
        -- the buffer under a failed request.
        -- A failed request ends the pass. Cancelling arrives here too,
        -- which is what makes :ConjureCancel stop the whole thing and not
        -- just the batch you were looking at.
        pass.active = false
        -- WHAT YOU STILL HAVE. A pass that dies on its fourth batch has
        -- already written three batches' worth of features, and they are
        -- kept — so the next `+` resumes from what is undescribed
        -- NOW rather than starting the project over. Saying only "failed"
        -- reads as losing the lot.
        local kept = pass.claims > 0
          and (" — %d claim(s) from %d earlier batch(es) are kept; + resumes from there"):format(
            pass.claims,
            pass.batches - 1
          )
          or " — `u` clears the block"
        vim.notify("[scry] draft failed: " .. err .. kept, vim.log.levels.WARN)
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
      -- Gather the blocks this batch re-opened into the features they
      -- belong to, before anything reads the buffer. It happens in the same
      -- tick as the splice, so `u` still undoes the batch as one thing.
      local kinds_now = require("scry.map").kinds_for(root)
      local tidied, folded = M.consolidate(vim.api.nvim_buf_get_lines(buf, 0, -1, false), kinds_now)
      if folded > 0 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, tidied)
      end

      vim.notify(
        ("[scry] drafted %d claim(s)%s — read them, edit what is right, `u` to discard"):format(
          #drafted,
          folded > 0 and (", %d added to features already here"):format(folded) or ""
        )
      )
      require("scry.glass").check()
      -- A batch that described nothing ends the pass. Otherwise the next
      -- one is issued from what is undescribed NOW — recomputed from the
      -- buffer rather than sliced off the old list, because the draft just
      -- claimed files and may well have claimed some outside its batch.
      --
      -- PROGRESS IS FILES DESCRIBED, NOT CLAIMS WRITTEN. This counted new
      -- claim ids, and a claim's id carries its feature name — so writing a
      -- second feature about a file already described produced a brand new
      -- id and read as progress. Paired with a kind that located nothing
      -- (see map.claim_path), that made the pass unable to finish: the same
      -- eleven pages came back undescribed every round, and the drafter,
      -- asked not to repeat existing feature NAMES, obliged by rewording.
      -- It ran to 301 features over 60 targets before it was stopped by
      -- hand.
      --
      -- The worklist is the only number that has to reach zero, so it is
      -- the one the guard watches.
      if pass.active then
        if survey then
          -- A survey is one request, not a loop: what it wrote is a page of
          -- sea-level features to READ, and rolling straight into
          -- file-grained batches would bury it under more text.
          pass.active = false
          pass.claims = pass.claims + #drafted
          vim.notify(
            ("[scry] high-level pass landed (%d claims) — read it, edit what is right, `u` discards; + again goes finer"):format(
              #drafted
            )
          )
        elseif #drafted == 0 then
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

--- Gather every block of a re-opened feature into the first one.
---
--- Re-opening is how a later batch adds to what an earlier one wrote (see
--- map.parse), and the parser has always read the blocks as one feature.
--- The BUFFER did not: four batches that each added to `Inspect how the
--- library maintains itself` left four `feature` lines with that name, so a
--- map of fourteen capabilities was written across twenty-eight headers and
--- read as a page of duplicates. The fragmentation the re-open move fixed
--- had turned into repetition.
---
--- Members keep their order and their own intent lines travel with them. A
--- member written twice is kept once — two batches naming the same route is
--- the same claim, not two.
---@param lines string[]
---@param known table<string, boolean|table> the kinds in force
---@return string[] lines, integer folded how many blocks were absorbed
function M.consolidate(lines, known)
  local order, blocks, lead = {}, {}, {}
  local headers = 0
  local current = nil
  for _, line in ipairs(lines) do
    local name = line:match("^feature%s+(.+)$")
    if name then
      name = vim.trim(name)
      headers = headers + 1
      if not blocks[name] then
        blocks[name] = { header = line, body = {}, blocks = 0 }
        order[#order + 1] = name
      end
      current = blocks[name]
      current.blocks = current.blocks + 1
    elseif current then
      current.body[#current.body + 1] = line
    else
      lead[#lead + 1] = line
    end
  end

  local out = {}
  vim.list_extend(out, lead)
  for _, name in ipairs(order) do
    local b = blocks[name]
    out[#out + 1] = b.header
    -- A member line and the indented lines under it are one unit.
    local seen, keep, dropping = {}, {}, false
    for _, line in ipairs(b.body) do
      local kind = line:match("^  ([%w_]+)%s+%S")
      if kind and known[kind] then
        dropping = seen[line] == true
        seen[line] = true
      elseif not line:match("^    %S") then
        dropping = false
      end
      if not dropping then
        keep[#keep + 1] = line
      end
    end
    -- A FEATURE WRITTEN ONCE IS LEFT EXACTLY AS IT WAS. Its blank lines are
    -- someone's layout and none of this function's business.
    --
    -- Where blocks were actually merged, the seams are: every contribution
    -- ends with a blank and the next begins right after it, so the members
    -- of one capability arrive in visually separated clumps by batch. The
    -- point of consolidating is that a feature reads as though it had been
    -- written once, so in that case the blanks go.
    local tidy = {}
    for _, line in ipairs(keep) do
      if b.blocks == 1 or vim.trim(line) ~= "" then
        tidy[#tidy + 1] = line
      end
    end
    while #tidy > 0 and vim.trim(tidy[#tidy]) == "" do
      table.remove(tidy)
    end
    vim.list_extend(out, tidy)
    out[#out + 1] = ""
  end
  return out, headers - #order
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
    pass.active, pass.batches, pass.claims, pass.unclaimed = true, 0, 0, nil
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
  -- THE WORKLIST HAS TO SHRINK. A batch that leaves as many files
  -- undescribed as it found them described nothing, whatever it wrote — and
  -- writing is what the old guard measured, which is how a pass reached 301
  -- features while eleven pages stayed on the list the whole time.
  if pass.unclaimed and #unclaimed >= pass.unclaimed then
    pass.active = false
    vim.notify(
      ("[scry] draft pass ended: %d file(s) still undescribed after a batch that changed nothing — "):format(
        #unclaimed
      ) .. ("read what it wrote, then + again (%d claims over %d batches)"):format(
        pass.claims,
        pass.batches
      ),
      vim.log.levels.WARN
    )
    return
  end
  pass.unclaimed = #unclaimed

  -- A BIG WORKLIST STARTS HIGH. Past five batches' worth of undescribed
  -- files, the first pass is a survey: one request over every path, a
  -- handful of sea-level features, coarse claims — the shape you want to
  -- read first anyway. Refinement comes later, corner by corner, once the
  -- worklist is small enough for the file-grained batches to make sense.
  local survey = begin and #unclaimed > BATCH * 5

  if pass.batches == 0 then
    vim.notify(
      survey and ("[scry] surveying %d undescribed file(s) at high level — one request"):format(#unclaimed)
        or ("[scry] scrying %d undescribed file(s) of %d"):format(#unclaimed, total)
    )
  end
  pass.batches = pass.batches + 1
  vim.api.nvim_buf_call(buf, function()
    M.draft(root, buf, map_, unclaimed, survey)
  end)
end

--- Gather re-opened blocks in the glass, on demand.
---
--- Drafting does this as each batch lands, so a pass run today needs no
--- tidying. This is for a map written before it did — or one you have been
--- re-opening features in by hand.
function M.tidy()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    vim.notify("[scry] open the glass first (:Scry)", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local tidied, folded = M.consolidate(lines, require("scry.map").kinds_for(state.root))
  if folded == 0 then
    vim.notify("[scry] every feature is already written once")
    return
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, tidied)
  glass.check()
  vim.notify(
    ("[scry] gathered %d re-opened block(s) into the features they belong to — `u` puts them back"):format(folded)
  )
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
  local unclaimed = require("scry.divergence").unclaimed(state.root, map_, require("scry.project").resolve(state.root))
  local warning = M.gate(#unclaimed)
  if warning then
    vim.notify(warning, vim.log.levels.WARN)
    return
  end

  M.next_batch(state.root, state.buf, true)
end

return M
