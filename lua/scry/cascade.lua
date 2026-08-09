-- The cascade: an absent claim becomes work. scry does NOT conjure — it
-- seeds the quickfix list with the target site and hands the intent to
-- conjurer's aggregate driver, which owns casting and per-site review.
--
-- A feature's prohibitions RIDE ALONG. Telling the generator the rules up
-- front is prevention; checking the code after it lands is detection; scry
-- does both, because a violation avoided beats one caught. What is still
-- withheld is the feature's SPEC PATHS from a code request — a request that
-- names the test is a request to satisfy the test, which is the one thing
-- an acceptance check must not be written to do (|scry-independence|).
--
-- Settlement: conjurer has no completion event and ripgrep reads DISK, so
-- the honest trigger for re-checking is "the file was saved". Nothing is
-- real until written — which is what the glass header already says.
local M = {}

-- The open cascade: { feature, target, files[], augroup }
local active = nil

--- Absolute, symlink-resolved path — the only form two spellings of the same
--- file reliably compare equal in.
---@param path string
---@return string
function M.norm(path)
  return vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

M._active = function()
  return active
end

--- Build everything that leaves scry for a cascadable claim. Pure: no side
--- effects, no buffer or list writes — so a spec can walk every outgoing
--- string and prove no withheld text rides along.
---
--- Two kinds cascade, and the order between them is the point. An
--- `exercises` claim conjures the CHECK; a `contains` claim conjures the
--- CODE. Doing the check first, and withholding it from the code request,
--- is what keeps a green result from meaning "the generator agreed with
--- itself" — see |scry-independence|.
---@param claim scry.Claim
---@param intent string
---@return { kind: string, items: table[], intent: string, file: string, symbol: string? }
function M.build(claim, intent)
  local file, symbol, text
  if claim.kind == "def" then
    file, symbol = claim.target:match("^(.-):([%w_.]+)$")
    if not file then
      -- The file-level form names a path and no symbol, so there is nothing
      -- to ask a generator for: "make this file exist" is not work. Name the
      -- definition you actually want and conjure that.
      error("[scry] nothing to conjure from `" .. claim.target .. "` — name a symbol (path:symbol)", 0)
    end
    -- The entry text becomes request.note in conjurer, so it says only what
    -- the claim says.
    text = ("scry: %s should define %s"):format(claim.feature, symbol)
  elseif claim.kind == "exercises" then
    file = claim.target:match("^([^:]+):") or claim.target
    symbol = claim.target:match("^[^:]+:(.+)$") -- the assertion label, if any
    text = symbol and ("scry: %s needs a spec asserting: %s"):format(claim.feature, symbol)
      or ("scry: %s needs a spec"):format(claim.feature)
  else
    error("[scry] :Conjure works on def and exercises claims (got " .. claim.kind .. ")", 0)
  end
  return {
    kind = claim.kind,
    file = file,
    symbol = symbol,
    intent = intent,
    items = {
      {
        filename = file,
        lnum = 1,
        col = 1,
        text = text,
        user_data = { scry = { feature = claim.feature, target = claim.target } },
      },
    },
  }
end

-- Re-check this feature's never-claims plus the seeding claim, against disk.
local function recheck(reason)
  if not active then
    return
  end
  local glass = require("scry.glass")
  local root = active.root
  local config = require("scry.project").resolve(root)
  local mapmod = require("scry.map")

  local m = mapmod.load(root .. "/" .. config.map_path)
  local nevers = {}
  for _, c in ipairs(m.claims) do
    if c.kind == "never" and c.feature == active.feature then
      nevers[#nevers + 1] = c
    end
  end
  if #nevers > 0 then
    local scoped = { lines = {}, features = m.features, claims = nevers }
    require("scry.check").run(scoped, {
      root = root,
      claims = nevers,
      resolver = require("scry.resolver").get(config.resolver ~= "" and config.resolver or nil),
    }, function(report)
      for _, c in ipairs(nevers) do
        local v = report.verdicts[mapmod.claim_id(c)]
        if v and v.status == "violated" then
          local e = v.evidence and v.evidence[1]
          vim.notify(
            ("[scry] never-claim VIOLATED (%s): %s%s"):format(
              reason,
              c.target,
              e and (" — " .. e.path .. ":" .. e.lnum) or ""
            ),
            vim.log.levels.WARN
          )
        end
      end
      glass.check()
    end)
  else
    glass.check()
  end
end

--- Seed the list from the claim under the cursor and (optionally) hand off
--- to conjurer. Registers a save-triggered re-check for the seeded file.
function M.start()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf) then
    vim.notify("[scry] :Conjure works on a claim line in the glass", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local m = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local claim
  for _, c in ipairs(m.claims) do
    if c.lnum == lnum then
      claim = c
      break
    end
  end
  if not claim then
    vim.notify("[scry] no claim on this line", vim.log.levels.WARN)
    return
  end
  if claim.kind ~= "def" and claim.kind ~= "exercises" then
    vim.notify(
      "[scry] :Conjure works on def and exercises claims (this is a " .. claim.kind .. " claim)",
      vim.log.levels.WARN
    )
    return
  end

  if claim.kind == "def" and not claim.target:match("^(.-):([%w_.]+)$") then
    vim.notify(
      "[scry] `" .. claim.target .. "` names a file, not a symbol — there is nothing to conjure from it",
      vim.log.levels.WARN
    )
    return
  end

  local default
  if claim.kind == "def" then
    default = "define " .. (claim.target:match(":([%w_.]+)$") or claim.target)
  else
    local label = claim.target:match("^[^:]+:(.+)$")
    default = label and ("write a spec asserting " .. label) or "write a spec for this feature"
  end

  vim.ui.input({ prompt = "Conjure: ", default = default }, function(intent)
    if not intent or intent == "" then
      return
    end
    M.seed(state.root, claim, intent, true)
  end)
end

--- The seeding half, separated so specs can drive it without vim.ui.
---@param root string
---@param claim scry.Claim
---@param intent string
---@param handoff boolean Call conjurer's :ConjureAll after seeding?
function M.seed(root, claim, intent, handoff)
  local config = require("scry.project").resolve(root)
  local built = M.build(claim, intent)
  local m = require("scry.map").load(root .. "/" .. config.map_path)

  -- THE FEATURE'S PROHIBITIONS RIDE ALONG. A rule the generator is told is
  -- a rule it can follow; the same rule is re-checked once the code lands
  -- (recheck), so telling costs nothing and prevents the redo round-trip.
  -- Scoped to this feature — a different feature's prohibition is never
  -- evaluated against this code, so it has no business in the request.
  local nevers = {}
  for _, c in ipairs(m.claims) do
    if c.kind == "never" and c.feature == claim.feature then
      nevers[#nevers + 1] = c.target
    end
  end
  if #nevers > 0 then
    built.intent = built.intent
      .. ("\nThe result must never contain text matching: %s"):format(table.concat(nevers, " · "))
  end

  -- What IS withheld from a code request: this feature's spec paths. A
  -- request that names the test is a request to satisfy the test, which is
  -- the one thing an acceptance check must not be written to do.
  -- Withholding the path is all scry can enforce — the spec itself lives in
  -- the tree and a generator that reads the repo will find it (see
  -- |scry-independence|). The tripwire makes the guarantee testable.
  if claim.kind == "def" then
    local spec_paths = {}
    for _, c in ipairs(m.claims) do
      if c.kind == "exercises" and c.feature == claim.feature then
        spec_paths[#spec_paths + 1] = c.target:match("^([^:]+):") or c.target
      end
    end
    for _, path in ipairs(spec_paths) do
      for _, s in ipairs({ built.intent, built.items[1].text }) do
        if s and path ~= "" and s:find(path, 1, true) then
          error(("[scry] independence leak: a spec path appears in an outgoing string (%q)"):format(path), 0)
        end
      end
    end
  end

  -- A claim can name a file that does not exist yet — that is the normal
  -- state of work not yet done. Conjurer rewrites a region of a buffer, so
  -- give it one.
  local abs = root .. "/" .. built.file
  if not vim.loop.fs_stat(abs) then
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    vim.fn.writefile({ "" }, abs)
    vim.notify(("[scry] created %s"):format(built.file))
  end

  vim.fn.setqflist({}, " ", {
    title = "scry: " .. claim.feature,
    items = built.items,
  })

  if active and active.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
  end
  local group = vim.api.nvim_create_augroup("scry.cascade", { clear = true })
  active = {
    root = root,
    feature = claim.feature,
    target = claim.target,
    files = { built.file },
    augroup = group,
  }
  -- Match on the resolved path in the callback rather than an autocmd
  -- pattern. Two traps live here: a seeded entry names its file relative to
  -- the root (so the buffer's name may be relative, and an absolute pattern
  -- would never match), and :p does not follow symlinks (on macOS /tmp is
  -- /private/tmp, so the two spellings of the same file compare unequal).
  -- resolve() on both sides settles both.
  local want = M.norm(root .. "/" .. built.file)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*",
    callback = function(args)
      if M.norm(args.file) == want then
        recheck("on save")
      end
    end,
  })

  if handoff then
    -- conjurer is a hard dependency: scry conjures through it, and there is
    -- no by-hand mode to fall back to.
    local ok, conjurer_qf = pcall(require, "conjurer.quickfix")
    if not ok then
      error("[scry] conjurer.nvim is required — install vim-pro/conjurer.nvim", 0)
    end
    conjurer_qf.all(built.intent)
  end
  return built
end

--- Clear the cascade's save watcher.
function M.stop()
  if active and active.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
  end
  active = nil
end

M._recheck = recheck

return M
