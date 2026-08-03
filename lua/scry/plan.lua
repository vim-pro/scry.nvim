-- The plan: what this intent will do, written where you can edit it.
--
-- Aiming used to stop at the cursor with the change entirely in your head.
-- You saw WHERE (the members) and you knew WHAT you asked for, but what
-- would actually happen — which files change, which get created, what goes
-- away — lived nowhere until the cast came back with it already done.
-- Review after the fact, on a tool whose whole shape is look-then-fire.
--
-- Now aiming ends in a plan, in the map's own grammar. Each member this
-- intent touches gets a note saying what will happen there, and a file that
-- needs creating arrives as a member whose verdict is already `✗ absent` —
-- which is what "to be added" looks like in a buffer that only says true
-- things:
--
--     route c/[slug]      src/pages/c/[slug].astro   ✓ present (file)
--       add a print button that opens the print view
--     route print         src/pages/print.astro      ✗ absent (no such file)
--       the print-only sheet: steps, notes, no chrome
--
-- THE PLAN IS BUFFER TEXT, not an overlay. That is the entire point.
-- Altering the suggestion is editing lines; discarding it is `u`; building
-- it is `~`, whose request already carries each member's note. There is no
-- accept/reject UI, because the review surface for a suggestion in a text
-- file is the text file.
--
-- THE MACHINE MAY NOT SHRINK THE MAP. A plan that omits an existing member
-- would silently narrow the feature, so apply() re-adds anything the model
-- dropped, with its original notes. Removing a member is an edit only YOU
-- make — `dd`, like anything else you delete. Removal of CONTENT is a note
-- like any other ("remove the dark-mode force"); deleting whole files is
-- outside the cast's power and stays yours.
local M = {}

-- THE PENDING PLAN, so the buffer can say which rows are part of it.
--
-- A plan note and a member's ordinary description are the same grammar —
-- deliberately, since an executed plan's notes ARE decent descriptions — so
-- the buffer alone cannot say "this row is about to change". This is that
-- knowledge: which feature has a live plan, and (after the cast) what
-- actually happened to each planned file.
--
-- Session state, like the last cast. It clears when the map is WRITTEN —
-- `:w` is the acceptance gesture — or when a new plan replaces it.
M.pending = nil

--- What the plan says about this member, if anything.
---
--- Before the cast: `change` or `create`, derived from the note and the
--- file — a noted member whose file exists will change, one whose file is
--- absent will be created. After the cast: what actually happened, which is
--- the closure — `changed`, `created`, or `skipped` for a planned member
--- the cast did not touch. A member with no note is not the plan's to mark.
---@param claim scry.Claim
---@param path string? the file this member names
---@param exists boolean
---@return "change"|"create"|"changed"|"created"|"skipped"|nil
function M.mark(claim, path, exists)
  if not M.pending or claim.feature ~= M.pending.feature then
    return nil
  end
  local noted = #(claim.desc or {}) > 0
  if M.pending.outcomes then
    local outcome = path and M.pending.outcomes[path]
    if outcome then
      return outcome
    end
    -- Planned, and the cast did not touch it. The one thing here worth a
    -- louder word: the notes still say what was supposed to happen.
    return noted and "skipped" or nil
  end
  if not noted then
    return nil
  end
  return exists and "change" or "create"
end

--- The cast happened: settle the plan against what it actually did.
---@param feature_name string
---@param res { changed: string[], created: string[] }
function M.settle(feature_name, res)
  if not (M.pending and M.pending.feature == feature_name) then
    return
  end
  local outcomes = {}
  for _, path in ipairs(res.changed or {}) do
    outcomes[path] = "changed"
  end
  for _, path in ipairs(res.created or {}) do
    outcomes[path] = "created"
  end
  M.pending.outcomes = outcomes
end

--- Forget the plan. `:w` calls this — writing the map is accepting it.
function M.clear()
  M.pending = nil
end

local SYSTEM = table.concat({
  "You are planning one change to a software product. The change is",
  "described by an INTENT, and it lands on one FEATURE — a thing a person",
  "can do, made of MEMBERS, each of which names a file.",
  "",
  "Output the feature's member list, annotated with what this intent will",
  "do. Exactly this shape, nothing else:",
  "",
  "<kind> <target>",
  "  <one line: what will happen in this file>",
  "<kind> <target>",
  "",
  "Rules:",
  "- Repeat EVERY existing member, in order. Never leave one out: a member",
  "  you omit silently shrinks the feature.",
  "- Put a note under a member ONLY if this intent touches its file. An",
  "  untouched member is repeated bare, with no note.",
  "- ADD members for files this change needs that are not members yet, using",
  "  the kinds listed. A kind with a path template may name a file that does",
  "  not exist — that is how a file gets created.",
  "- Something to REMOVE from a file is a note on that member, starting",
  "  with `remove`. Files themselves are never deleted.",
  "- Notes are one line, concrete, and start with a verb.",
  "- No prose outside the shape. No fences, no headings, no commentary.",
}, "\n")

--- Everything that leaves scry to plan a change.
---
--- Pure: no buffers, no provider, no disk. A spec reads every outgoing byte.
---@param feature scry.Feature
---@param intent string
---@param kindset table<string, table>
---@param files string[] repo-relative paths the project has
---@param claimed table<string, string>? path -> feature already claiming it
---@param read fun(path: string): string[]|nil
---@return { system: string, user: string }
function M.request(feature, intent, kindset, files, claimed, read)
  local mapmod = require("scry.map")
  local out = { "FEATURE: " .. feature.name }
  if #(feature.desc or {}) > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "WHAT IT IS FOR:"
    for _, line in ipairs(feature.desc) do
      out[#out + 1] = "  " .. line
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "INTENT:"
  out[#out + 1] = "  " .. intent

  out[#out + 1] = ""
  if #feature.claims == 0 then
    -- Stated rather than left as an empty heading: a bare feature's plan IS
    -- its first members, and the model should know it is building from
    -- nothing rather than repeating an empty list.
    out[#out + 1] = "CURRENT MEMBERS: (none yet — every member you emit is new)"
  else
    out[#out + 1] = "CURRENT MEMBERS:"
    for _, claim in ipairs(feature.claims) do
      local path = mapmod.claim_path(claim, kindset)
      local exists = path and read(path) ~= nil
      out[#out + 1] = ("  %s %s%s%s"):format(
        claim.kind,
        claim.target,
        path and ("  ->  " .. path) or "",
        exists and "" or "   (DOES NOT EXIST YET)"
      )
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "KINDS YOU MAY USE:"
  local names = {}
  for kind in pairs(kindset or {}) do
    names[#names + 1] = kind
  end
  table.sort(names)
  for _, kind in ipairs(names) do
    local spec = kindset[kind]
    if type(spec) == "table" and spec.path then
      out[#out + 1] = ("  %s <name>    the file %s"):format(kind, spec.path)
    else
      out[#out + 1] = ("  %s <path>"):format(kind)
    end
  end

  out[#out + 1] = ""
  out[#out + 1] = "FILES IN THIS PROJECT:"
  for _, path in ipairs(files) do
    local owner = claimed and claimed[path]
    out[#out + 1] = owner and ("  %s   (already part of: %s)"):format(path, owner) or ("  " .. path)
  end

  -- The contents of the members that exist. A plan written without reading
  -- the code says "update the stylesheet"; one written with it says which
  -- rule to remove. The cast will see these files anyway — the plan is the
  -- same look, earlier, when it can still change your mind.
  for _, claim in ipairs(feature.claims) do
    local path = mapmod.claim_path(claim, kindset)
    local lines = path and read(path)
    if lines then
      out[#out + 1] = ""
      out[#out + 1] = "--- " .. path .. " ---"
      vim.list_extend(out, lines)
    end
  end

  return { system = SYSTEM, user = table.concat(out, "\n") }
end

--- Read a plan back into members with their notes.
---
--- The same rule as everywhere: a line is a member only when its first word
--- is a kind this project knows. Anything else attaches to the member above
--- it as a note — and before the first member it is commentary, dropped.
---@param result string
---@param kindset table<string, table>
---@return { kind: string, target: string, notes: string[] }[]
function M.parse(result, kindset)
  local members = {}
  local current = nil
  for _, raw in ipairs(vim.split(result or "", "\n", { plain = true })) do
    local line = vim.trim(raw)
    local bare = line:gsub("<[%a_]+>", ""):gsub("%s", "")
    if line ~= "" and not line:match("^```") and not (line:find("<") and bare == "") then
      local kind, target = line:match("^([%w_]+)%s+(%S.*)$")
      if kind and kindset[kind] then
        current = { kind = kind, target = vim.trim(target), notes = {} }
        members[#members + 1] = current
      elseif current then
        current.notes[#current.notes + 1] = line
      end
      -- Before the first member: the model clearing its throat. Dropped.
    end
  end
  return members
end

--- Write the plan into the feature's block, as one undoable edit.
---
--- The feature's own description is untouched — the plan is about members.
--- Anything the model dropped is re-added with its original notes, because
--- the machine may not shrink the map; and a planned member that already
--- lives in ANOTHER block of a re-opened feature is skipped rather than
--- duplicated here.
---@param buf integer
---@param feature scry.Feature
---@param kindset table<string, table>
---@param planned { kind: string, target: string, notes: string[] }[]
---@return integer first line of the written region
function M.apply(buf, feature, kindset, planned)
  local glass = require("scry.glass")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local h = (feature.lnums or { feature.lnum })[1]

  -- The block: from the header to the line before the next feature (or EOF).
  local block_end = #lines
  for i = h + 1, #lines do
    if lines[i]:match("^feature%s") then
      block_end = i - 1
      break
    end
  end
  -- Trailing blanks are the separator between features, not body.
  local trailing = 0
  while block_end - trailing > h and vim.trim(lines[block_end - trailing]) == "" do
    trailing = trailing + 1
  end
  local body_end = block_end - trailing

  -- The description stays: contiguous two-space prose right under the
  -- header, before any member. The plan replaces what follows it.
  local body_start = h + 1
  while
    body_start <= body_end
    and lines[body_start]:match("^  %S")
    and not glass.is_member_line(lines[body_start], kindset)
  do
    body_start = body_start + 1
  end

  -- Members of a re-opened feature living in OTHER blocks: not ours to move.
  local elsewhere = {}
  for _, claim in ipairs(feature.claims) do
    if claim.lnum < h or claim.lnum > block_end then
      elsewhere[claim.kind .. "\1" .. claim.target] = true
    end
  end

  local out, seen = {}, {}
  for _, m in ipairs(planned) do
    local id = m.kind .. "\1" .. m.target
    if not elsewhere[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = "  " .. m.kind .. " " .. m.target
      for _, note in ipairs(m.notes) do
        out[#out + 1] = "    " .. note
      end
    end
  end

  -- THE MACHINE MAY NOT SHRINK THE MAP. Anything it dropped comes back, in
  -- place, with the notes it already had. Removing a member is `dd` — yours.
  for _, claim in ipairs(feature.claims) do
    local id = claim.kind .. "\1" .. claim.target
    if not seen[id] and not elsewhere[id] then
      seen[id] = true
      out[#out + 1] = "  " .. claim.kind .. " " .. claim.target
      for _, note in ipairs(claim.desc or {}) do
        out[#out + 1] = "    " .. note
      end
    end
  end

  for _ = 1, trailing do
    out[#out + 1] = ""
  end
  vim.api.nvim_buf_set_lines(buf, body_start - 1, block_end, false, out)
  return body_start
end

--- Plan a change: one provider call, ending in an edited buffer.
---@param root string
---@param buf integer the glass buffer
---@param feature scry.Feature
---@param intent string
---@param done fun(changed: integer, created: integer)? for specs
function M.give(root, buf, feature, intent, done)
  local mapmod = require("scry.map")
  local kindset = mapmod.kinds_for(root)
  local config = require("scry.project").resolve(root)
  local files = require("scry.divergence").sources(root, config)

  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), kindset)
  local claimed = {}
  for _, f in ipairs(map_.features) do
    for _, path in ipairs(mapmod.footprint(f, kindset)) do
      claimed[path] = f.name
    end
  end
  local function read(path)
    local full = root .. "/" .. path
    if vim.fn.filereadable(full) ~= 1 then
      return nil
    end
    return vim.fn.readfile(full)
  end

  local built = M.request(feature, intent, kindset, files, claimed, read)

  local ns = vim.api.nvim_create_namespace("scry_plan")
  local at = (feature.lnums or { feature.lnum })[1] - 1
  local started = vim.uv.hrtime()
  local function say(text)
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, at, 0, {
        virt_text = { { "  ✨ " .. text, "ScryBuilding" } },
        virt_text_pos = "eol",
      })
    end
  end
  say("planning the change…")

  require("conjurer").get_provider()({
    config = require("conjurer").config or {},
    system = built.system,
    user = built.user,
    intent = intent,
    cwd = root,
    timeout_ms = 300000,
    on_narrate = function(line)
      say(("%s  %ds"):format(line:sub(1, 60), math.floor((vim.uv.hrtime() - started) / 1e9)))
    end,
  }, function(err, result)
    vim.schedule(function()
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      if err then
        vim.notify("[scry] " .. feature.name .. ": " .. err, vim.log.levels.ERROR)
        return
      end
      local planned = M.parse(result, kindset)
      if #planned == 0 then
        vim.notify(
          ("[scry] no plan came back for `%s` — say the intent differently, or edit the members yourself"):format(
            intent
          ),
          vim.log.levels.WARN
        )
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      M.apply(buf, feature, kindset, planned)
      M.pending = { feature = feature.name }
      pcall(vim.cmd, "normal! zv")

      -- The numbers a reader wants before deciding: how much of this is
      -- edits and how much is new files.
      local changed, created = 0, 0
      for _, m in ipairs(planned) do
        if #m.notes > 0 then
          local path = mapmod.claim_path({ kind = m.kind, target = m.target }, kindset)
          if path and read(path) then
            changed = changed + 1
          else
            created = created + 1
          end
        end
      end
      vim.notify(
        ("[scry] the plan is in the buffer — %d to change, %d to create · edit it, then ~ · u to discard"):format(
          changed,
          created
        )
      )
      require("scry.glass").check()
      if done then
        done(changed, created)
      end
    end)
  end)
end

return M
