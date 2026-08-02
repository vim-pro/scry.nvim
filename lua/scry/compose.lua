-- Programming at the altitude of a capability.
--
-- Vim's bargain is an operator applied to a precisely addressed noun:
-- `d2w`, `ci"`, `>ap`. Conjurer ported that to generated edits — `~{motion}`
-- rewrites a region toward an intent. This raises the noun. The thing you
-- aim at is not a region in a file, it is a FEATURE, and the change lands on
-- its footprint — every file it is made of.
--
-- So: cursor on a feature, say what you want, and the change lands across
-- every file in its footprint at once. You do not open the files. That is
-- the point — nobody works a file at a time any more, and a capability that
-- spans four files is one thought, not four.
--
-- ONE CAST, NOT ONE PER FILE. The alternative is to seed the footprint into
-- a quickfix list and let conjurer's aggregate driver visit each site with
-- the same intent (|scry-cascade| does exactly that for a single claim).
-- That is cheaper and reviewable a site at a time, but no single request
-- ever sees the whole capability — and a change that has to stay coherent
-- across files is precisely the change worth making here. A page and the
-- endpoint it posts to have to agree.
--
-- A MEMBER NAMES ITS FILE BEFORE THE FILE EXISTS. The path comes from its
-- kind's probe (see scry.map.claim_path), so `route print` names
-- src/pages/print.astro whether or not anything is there yet. Adding a
-- capability and changing one are therefore the same verb: write the
-- feature you want with the members it should have, and cast. Absent
-- members are files to create; present ones are files to change.
--
-- REVIEW IS VIM'S, NOT OURS. Results land in BUFFERS and are left modified
-- and unsaved. Nothing touches the disk. That gives you every tool you
-- already have — `u` per buffer, `:diffthis` against the file on disk,
-- `:w` what you want and `:e!` what you don't — and spares this from
-- inventing a review UI that would be worse than the one you know.
local M = {}

-- The output protocol. One block per file, the whole file inside it, so
-- applying a result is a buffer replacement rather than a patch — there is
-- no hunk to misapply and no line numbers to drift.
local OPEN = "<<<FILE "
local CLOSE = "FILE>>>"

-- THE LAST CAST, so it can be taken back.
--
-- `d2w` has `u`. A cast across four files had `:e!`, once per file, from a
-- list of paths you had to remember — which meant that in practice the way
-- to undo one was git. An operator you cannot reverse is not an operator,
-- it is a commitment.
--
-- Only what is still UNSAVED can be reversed, and that is the honest limit:
-- once you `:w`, the change is yours and git is the right tool. Discard says
-- which files it could not take back rather than reporting a clean sweep it
-- did not perform.
--
-- Declared here, at the top, rather than beside M.discard where it reads
-- best: M.apply is defined above that point, so the assignment inside it
-- bound a GLOBAL instead of this local, and every cast recorded nothing.
local last = nil

local SYSTEM = table.concat({
  "You are editing a software project at the level of a FEATURE — one thing",
  "a person can do, implemented across several files.",
  "",
  "You are given the feature, what it is for, the files it is made of, and",
  "the current contents of the ones that exist. You are given an intent.",
  "Carry out that intent across those files, keeping them consistent with",
  "each other: if a page and the endpoint it calls must agree, make them",
  "agree.",
  "",
  "OUTPUT PROTOCOL. For every file you change or create, emit:",
  "",
  OPEN .. "<path exactly as given>",
  "<the complete new contents of the file>",
  CLOSE,
  "",
  "Rules:",
  "- Emit a block ONLY for files you actually change. Leave the rest out.",
  "- Emit the WHOLE file, not a diff and not an excerpt.",
  "- Never emit a path you were not given.",
  "- No prose, no fences, no commentary outside the blocks.",
}, "\n")

--- Everything that leaves scry for a whole-feature cast.
---
--- Pure: no buffers, no disk writes, no provider. A spec can read every
--- outgoing byte.
---@param root string
---@param feature scry.Feature
---@param intent string
---@param kinds table the kinds in force, for member paths
---@param read fun(path: string): string[]|nil reads a file, nil if absent
---@return { system: string, user: string, files: { path: string, exists: boolean }[] }
function M.request(root, feature, intent, kinds, read)
  local mapmod = require("scry.map")
  local files, seen = {}, {}
  for _, claim in ipairs(feature.claims) do
    local path = mapmod.claim_path(claim, kinds)
    if path and not seen[path] then
      seen[path] = true
      files[#files + 1] = { path = path, exists = read(path) ~= nil, claim = claim }
    end
  end

  local out = {
    "FEATURE: " .. feature.name,
  }
  if feature.desc and #feature.desc > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "WHAT IT IS FOR:"
    for _, line in ipairs(feature.desc) do
      out[#out + 1] = "  " .. line
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "WHAT IT IS MADE OF:"
  for _, f in ipairs(files) do
    local note = f.claim.desc and f.claim.desc[1]
    out[#out + 1] = ("  %s %s -> %s%s"):format(
      f.claim.kind,
      f.claim.target,
      f.path,
      f.exists and "" or "   (DOES NOT EXIST YET — create it)"
    )
    if note then
      out[#out + 1] = "      " .. note
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "INTENT:"
  out[#out + 1] = "  " .. intent

  for _, f in ipairs(files) do
    local lines = read(f.path)
    out[#out + 1] = ""
    if lines then
      out[#out + 1] = OPEN .. f.path
      vim.list_extend(out, lines)
      out[#out + 1] = CLOSE
    else
      out[#out + 1] = ("(%s does not exist yet)"):format(f.path)
    end
  end

  return { system = SYSTEM, user = table.concat(out, "\n"), files = files }
end

--- Read file blocks out of a result.
---
--- Tolerant of the model's usual habits — a fence around the whole answer,
--- a stray blank line — and strict about the one thing that matters: a
--- block that never closes is DROPPED rather than half-applied. A truncated
--- response is the common failure (a cast that hits max_tokens mid-file),
--- and writing half a file into a buffer is worse than writing none.
---@param result string
---@return { path: string, lines: string[] }[]
function M.parse(result)
  local out = {}
  local path, body = nil, nil
  for _, line in ipairs(vim.split(result or "", "\n", { plain = true })) do
    if path then
      if vim.trim(line) == CLOSE then
        out[#out + 1] = { path = path, lines = body }
        path, body = nil, nil
      else
        body[#body + 1] = line
      end
    else
      local opened = line:match("^%s*" .. vim.pesc(OPEN) .. "(.+)$")
      if opened then
        path, body = vim.trim(opened), {}
      end
    end
  end
  -- `path` still set here means the last block never closed. Deliberately
  -- discarded: see above.
  return out
end

--- Put the results into buffers, modified and unsaved.
---
--- Nothing is written to disk. What you get is what you would have if you
--- had made the edits yourself and not saved — so `u` undoes, `:w` commits,
--- `:e!` discards, and `:diffthis` compares against what is on disk.
---@param root string
---@param files { path: string, lines: string[] }[]
---@param allowed table<string, true>? paths the cast was permitted to touch
---@return { changed: string[], created: string[], refused: string[] }
function M.apply(root, files, allowed)
  local changed, created, refused = {}, {}, {}
  -- Recorded HERE rather than at the end of a cast, because this is the
  -- moment anything is touched. Any path that applies is a path that has to
  -- be reversible; hanging the record off the caller would mean a future
  -- second caller silently had no undo.
  last = { root = root, files = {} }
  for _, f in ipairs(files) do
    -- A cast may only edit what it was shown. A path it invented is a path
    -- nobody named, and writing it would make the map a liar about what the
    -- feature is made of.
    if allowed and not allowed[f.path] then
      refused[#refused + 1] = f.path
    else
      local full = root .. "/" .. f.path
      local existed = vim.fn.filereadable(full) == 1
      if not existed then
        vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
      end
      local buf = vim.fn.bufadd(full)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, f.lines)
      table.insert(last.files, { path = f.path, created = not existed })
      if existed then
        changed[#changed + 1] = f.path
      else
        created[#created + 1] = f.path
      end
    end
  end
  return { changed = changed, created = created, refused = refused }
end

--- Put a cast's results where changes go, and land in the first one.
---
--- The old ending was a summary printed to the message line — longer than a
--- window, so every SUCCESSFUL cast finished at a `Press ENTER` prompt, and
--- then left you typing `:b` with paths you had to recall. Eight steps to
--- answer "did it do what I asked".
---
--- The list is the answer: `]q` walks the change, `u` undoes a file, `:w`
--- keeps one. All keys you already have.
---@param root string
---@param intent string
---@param res { changed: string[], created: string[], refused: string[] }
local function seed(root, intent, res)
  local items = {}
  local function add(paths, what)
    for _, path in ipairs(paths) do
      items[#items + 1] = {
        filename = root .. "/" .. path,
        lnum = 1,
        col = 1,
        text = what,
        user_data = { scry = { cast = true } },
      }
    end
  end
  add(res.changed, "changed")
  add(res.created, "created")
  if #items == 0 then
    return
  end
  vim.fn.setqflist({}, " ", { title = "scry: " .. intent, items = items })
  -- Land IN the change rather than in a message about it. cfirst opens the
  -- first file in the current window, which is the glass — deliberate: you
  -- came here to change the product, not to look at the map.
  pcall(vim.cmd, "cfirst")
end
M._seed = seed -- exposed for specs

--- Take back the last cast, as far as it can honestly be taken back.
function M.discard()
  if not last then
    vim.notify("[scry] no cast to discard", vim.log.levels.WARN)
    return
  end
  local dropped, kept = 0, {}
  for _, f in ipairs(last.files) do
    local full = last.root .. "/" .. f.path
    local buf = vim.fn.bufnr(full)
    if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
      if not vim.bo[buf].modified then
        -- Saved since the cast. Reloading would not undo it, and reverting
        -- the file on disk is git's job and not something to do behind
        -- someone's back.
        kept[#kept + 1] = f.path
      elseif f.created then
        -- Nothing on disk to reload FROM: the cast invented this file, so
        -- taking it back means the buffer goes.
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        dropped = dropped + 1
      else
        vim.api.nvim_buf_call(buf, function()
          pcall(vim.cmd, "edit!")
        end)
        dropped = dropped + 1
      end
    end
  end
  last = nil
  local msg = ("[scry] dropped %d unsaved file(s)"):format(dropped)
  if #kept > 0 then
    msg = msg .. (" · %d already saved, use git: %s"):format(#kept, table.concat(kept, " "))
  end
  vim.notify(msg)
  require("scry.glass").check()
end

--- The feature under the cursor, from the glass.
---@return scry.Feature?, table state
function M.at_cursor()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.root) then
    return nil, state
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local mapmod = require("scry.map")
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local found
  for _, f in ipairs(map_.features) do
    for _, at in ipairs(f.lnums or { f.lnum }) do
      if at <= lnum and (not found or at > found.at) then
        found = { feature = f, at = at }
      end
    end
  end
  return found and found.feature or nil, state
end

-- THE INTENT YOU ALREADY GAVE. `:Scry {intent}` aims you at a capability
-- (|scry-aim|) and then stops, so you see the files before anything is cast
-- across them. Making you retype the intent at that point would be asking the
-- same question twice — so `~` comes up pre-filled, and agreeing costs one
-- keystroke while disagreeing costs an edit.
local pending = nil

--- Remember an intent for the next `~`.
---@param intent string?
function M.remember(intent)
  pending = intent
end

--- Cast an intent across a whole feature.
function M.start()
  local feature, state = M.at_cursor()
  if not feature then
    vim.notify("[scry] put the cursor on a feature in the glass (:Scry)", vim.log.levels.WARN)
    return
  end
  if not pcall(require, "conjurer") then
    error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
  end

  -- Cleared on use, not on success. A remembered intent that survived a
  -- cancelled prompt would come back on an unrelated feature later, which is
  -- the worst way for a convenience to behave.
  local prefill = pending
  pending = nil
  vim.ui.input({ prompt = ("Conjure %s: "):format(feature.name), default = prefill }, function(intent)
    if not intent or vim.trim(intent) == "" then
      return
    end
    M.cast(state.root, state.buf, feature, intent)
  end)
end

--- The casting half, separated so a spec can drive it without vim.ui.
---@param root string
---@param buf integer the glass buffer, for progress
---@param feature scry.Feature
---@param intent string
---@param done fun(res: table)? called with the apply result
function M.cast(root, buf, feature, intent, done)
  local mapmod = require("scry.map")
  local kinds = mapmod.kinds_for(root)
  local function read(path)
    local full = root .. "/" .. path
    if vim.fn.filereadable(full) ~= 1 then
      return nil
    end
    return vim.fn.readfile(full)
  end

  local built = M.request(root, feature, intent, kinds, read)
  if #built.files == 0 then
    vim.notify(
      ("[scry] %s locates no files — give it members before casting across it"):format(feature.name),
      vim.log.levels.WARN
    )
    return
  end

  local allowed = {}
  for _, f in ipairs(built.files) do
    allowed[f.path] = true
  end

  -- Progress on the feature's own line, because that is the thing you are
  -- operating on and the place you are looking.
  local ns = vim.api.nvim_create_namespace("scry_compose")
  local at = (feature.lnums or { feature.lnum })[1] - 1
  local started = vim.uv.hrtime()
  local function say(text, hl)
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, at, 0, {
        virt_text = { { "  ✨ " .. text, hl or "ScryBuilding" } },
        virt_text_pos = "eol",
      })
    end
  end
  say(("casting across %d file(s)…"):format(#built.files))

  local config = require("conjurer").config or {}
  require("conjurer").get_provider()({
    config = config,
    system = built.system,
    user = built.user,
    intent = intent,
    cwd = root,
    -- A whole feature is a bigger ask than a region, and every file comes
    -- back whole rather than as a diff.
    timeout_ms = 900000,
    max_tokens = 64000,
    on_narrate = function(line)
      local elapsed = math.floor((vim.uv.hrtime() - started) / 1e9)
      say(("%s  %ds"):format(line:sub(1, 60), elapsed))
    end,
  }, function(err, result)
    vim.schedule(function()
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      if err then
        vim.notify("[scry] " .. feature.name .. ": " .. err, vim.log.levels.ERROR)
        return
      end
      local parsed = M.parse(result)
      if #parsed == 0 then
        vim.notify(
          ("[scry] %s: the cast returned no file blocks — nothing changed"):format(feature.name),
          vim.log.levels.WARN
        )
        return
      end
      local res = M.apply(root, parsed, allowed)
      require("scry.glass").check()
      seed(root, intent, res)

      -- SHORT ENOUGH NOT TO NEED A KEYPRESS. The old summary overflowed the
      -- window, so vim ended every successful cast with `Press ENTER` — a
      -- prompt to dismiss, on the one gesture that is supposed to feel like
      -- `d2w`. What it has to say is where the change is and how to take it
      -- back; the rest is |scry-compose|.
      local n = #res.changed + #res.created
      local msg = ("[scry] %d file%s · ]q next · :ScryDiscard undoes it"):format(n, n == 1 and "" or "s")
      if #res.refused > 0 then
        -- Never folded into the count. A refused path is a file the cast
        -- tried to write that nobody named, and it is the one thing here
        -- worth interrupting for.
        msg = msg .. (" · %d REFUSED"):format(#res.refused)
      end
      vim.notify(msg)
      if done then
        done(res)
      end
    end)
  end)
end

return M
