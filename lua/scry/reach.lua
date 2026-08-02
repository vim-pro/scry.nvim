-- Reach: what a feature actually touches, computed rather than listed.
--
-- This is the piece that decides whether a map stays readable. A feature's
-- members are its ENTRY POINTS — the route someone visits, the command they
-- run — and the code behind them is not something anyone should have to
-- enumerate. Drafted over a real project without this, scry produced
-- eighty-six hand-listed members; the archived vim.pro's manifests, which
-- had it, ran to fifteen lines and said more.
--
-- WHAT THE ENGINE IS FOR, precisely. Stack graphs do name resolution: given
-- a position that uses a name, they answer which definition that name binds
-- to, across files, following imports and scope. That is the question
-- ripgrep cannot answer and the reason a text search over-reports — every
-- `parse` in the project matches, and one of them is yours.
--
-- So reach is computed in two passes, and the split is the honesty:
--
--   CANDIDATES  ripgrep finds every position that mentions the name. Fast,
--               over-broad, and never reported as more than it is.
--   RESOLVED    the engine is asked, for each candidate, whether it binds
--               to THIS definition. What survives is reach.
--
-- Without the engine the first pass still runs and the answer is labeled
-- `text` rather than `resolved`, because a name match is evidence of a
-- mention and nothing else. Two files called the same thing are two files,
-- and scry says which kind of answer it has every time it gives one.
local M = {}

-- Language -> the crate that resolves it. These are the languages stack
-- graphs actually has definitions for; anything else has no engine and is
-- answered by text, out loud.
local ENGINE = {
  javascript = "tree-sitter-stack-graphs-javascript",
  typescript = "tree-sitter-stack-graphs-typescript",
  tsx = "tree-sitter-stack-graphs-typescript",
  python = "tree-sitter-stack-graphs-python",
  java = "tree-sitter-stack-graphs-java",
}

local EXT_LANG = {
  js = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  jsx = "javascript",
  ts = "typescript",
  mts = "typescript",
  tsx = "tsx",
  py = "python",
  java = "java",
}

--- The language of a path, or nil.
---@param path string
---@return string?
function M.lang_of(path)
  return EXT_LANG[(path:match("%.([%w]+)$") or ""):lower()]
end

--- The engine binary for a language, or nil if it is not provisioned.
---
--- Scry's own directory is preferred over PATH so a provisioned engine is
--- scry's to manage and cannot be shadowed by an unrelated install.
---@param lang string?
---@return string?
function M.engine(lang)
  local crate = lang and ENGINE[lang]
  if not crate then
    return nil
  end
  local owned = vim.fn.stdpath("data") .. "/scry/bin/" .. crate
  if vim.fn.executable(owned) == 1 then
    return owned
  end
  return vim.fn.executable(crate) == 1 and crate or nil
end

--- Where this project's index lives. ONE database for the whole project,
--- every language in it.
---
--- It was one per language, and that was the bug behind a whole wrong
--- conclusion: a TypeScript page importing a JavaScript module resolved to
--- nothing, and I read that as stack graphs being unable to cross a
--- language boundary. They cross it perfectly well — the .js file simply
--- was not in the database the query ran against. Different engines
--- indexing into a SHARED database produce a graph that joins, which is
--- measurable in three separate ways and now has a spec.
---@param root string
---@return string
function M.db(root)
  local key = root:gsub("[^%w]", "%%")
  local dir = vim.fn.stdpath("cache") .. "/scry"
  vim.fn.mkdir(dir, "p")
  return ("%s/%s.sqlite"):format(dir, key)
end

--- Index a project's sources for `lang`. Slow, and the only slow thing
--- here — the query pass reuses this.
---@param root string
---@param lang string
---@param files string[] repo-relative
---@param cb fun(ok: boolean, err: string?)
function M.index(root, lang, files, cb)
  local bin = M.engine(lang)
  if not bin or #files == 0 then
    cb(false, "no engine for " .. tostring(lang))
    return
  end
  -- --hide-error-details because a file the grammar chokes on is normal in
  -- a real repo and its stack trace is not scry's news to deliver.
  local args = { bin, "index", "-D", M.db(root), "--hide-error-details" }
  vim.list_extend(args, files)
  vim.system(args, { cwd = root, text = true }, function(res)
    cb(res.code == 0, res.code ~= 0 and (res.stderr or ("exit " .. res.code)) or nil)
  end)
end

--- Parse `query definition` output.
---
--- Read off the engine, not off documentation. The real shape:
---
---   /abs/src/page.ts:2:11: found 2 definitions for 1 references
---   queried reference
---   /abs/src/page.ts:2:11:
---   2 | const x = initChecklist("a");
---     |           ^^^^^^^^^^^^^
---
---   has 2 definitions          <- `has definition` when there is one
---   /abs/src/lib.ts:1:17:
---   1 | export function initChecklist(id: string) {
---
--- Three things that a parser written from the older shape got wrong, and
--- each would have failed silently by reporting nothing:
---
---   * the marker is `has N definitions` / `has no definitions`, never
---     `has definitions:`;
---   * PATHS COME BACK ABSOLUTE even when the query was relative, so they
---     are made relative to the root before anything is compared;
---   * the queried reference is echoed with its own position BEFORE the
---     marker, so collecting locations without waiting for it would file
---     the reference as its own definition.
---
--- Source excerpts (`2 | code`, `  |  ^^^`) cannot be confused with a
--- location: only a location is path:line:col with a trailing colon.
--- Anything unmatched is ignored rather than guessed at — a misread line
--- would invent a binding, which is the one error this module exists to
--- prevent.
--- `real` is the root with symlinks resolved, and it is not optional on
--- macOS. The engine prints the REAL path — /private/var/... — while
--- vim.fn.tempname() and a user's own cwd say /var/..., so stripping only
--- the root as given leaves every path absolute, every comparison fails,
--- and reach reports zero for a symbol with references. It reports zero
--- rather than erroring, which is why this needs a spec and not a comment.
---@param out string
---@param root string? absolute paths are reported relative to this
---@param real string? the same root with symlinks resolved
---@return table<string, { path: string, lnum: integer }[]>
function M.parse_query(out, root, real)
  local prefixes = {}
  for _, r in ipairs({ root, real }) do
    if r and r ~= "" then
      prefixes[#prefixes + 1] = r:gsub("/*$", "") .. "/"
    end
  end
  local function rel(p)
    for _, prefix in ipairs(prefixes) do
      if p:sub(1, #prefix) == prefix then
        return p:sub(#prefix + 1)
      end
    end
    return p
  end
  local defs, cur, in_defs = {}, nil, false
  for line in (out or ""):gmatch("[^\n]+") do
    local p, l, c = line:match("^(.+):(%d+):(%d+): found ")
    if p then
      cur = ("%s:%s:%s"):format(rel(p), l, c)
      defs[cur] = defs[cur] or {}
      in_defs = false
    elseif line:match("^has no definition") then
      in_defs = false
    elseif line:match("^has definition") or line:match("^has %d+ definition") then
      -- THREE spellings, not two. The engine writes `has 2 definitions`
      -- when there are several and `has definition` — singular, with NO
      -- count — when there is exactly one. Matching only the counted form
      -- dropped every single-definition resolution, which is the common
      -- case, so reach reported zero for files whose imports resolve
      -- perfectly. It cost a wrong conclusion about stack graphs before it
      -- cost a wrong number.
      in_defs = true
    elseif in_defs and cur then
      local dp, dl = line:match("^(.+):(%d+):%d+:%s*$")
      if dp then
        table.insert(defs[cur], { path = rel(dp), lnum = tonumber(dl) })
      end
    end
  end
  return defs
end

--- Keep the candidates that genuinely bind to `target`.
---
--- A candidate survives only if the engine reports a definition at the
--- target's own location. That is the whole filter, and it is why the
--- result can be called resolved: nothing is kept because its name matched.
---@param candidates { path: string, lnum: integer, col: integer }[]
---@param target { path: string, lnum: integer }
---@param defs table<string, { path: string, lnum: integer }[]>
---@return table[] kept
function M.keep_bound(candidates, target, defs)
  local kept = {}
  for _, c in ipairs(candidates) do
    for _, d in ipairs(defs[("%s:%d:%d"):format(c.path, c.lnum, c.col)] or {}) do
      if d.path == target.path and d.lnum == target.lnum then
        kept[#kept + 1] = c
        break
      end
    end
  end
  return kept
end

--- Ask the engine which of `candidates` bind to `target`.
---@param root string
---@param lang string
---@param candidates table[]
---@param target { path: string, lnum: integer }
---@param cb fun(kept: table[]?, err: string?)
function M.resolve(root, lang, candidates, target, cb)
  local bin = M.engine(lang)
  if not bin then
    cb(nil, "no engine for " .. tostring(lang))
    return
  end
  if #candidates == 0 then
    cb({}, nil)
    return
  end
  local args = { bin, "query", "-D", M.db(root), "definition" }
  for _, c in ipairs(candidates) do
    args[#args + 1] = ("%s:%d:%d"):format(c.path, c.lnum, c.col)
  end
  -- Resolved HERE, before the subprocess: vim.fn is forbidden in the
  -- callback's fast event context.
  local real = vim.fn.resolve(vim.fn.fnamemodify(root, ":p"))
  vim.system(args, { cwd = root, text = true }, function(res)
    if res.code ~= 0 then
      cb(nil, res.stderr or ("exit " .. res.code))
      return
    end
    cb(M.keep_bound(candidates, target, M.parse_query(res.stdout or "", root, real)), nil)
  end)
end

--- Candidate positions that mention `name`, from ripgrep.
---
--- Over-broad on purpose and never reported as more than it is: this is
--- every place the token occurs, including the definition itself, comments,
--- and a same-named function in an unrelated file. It is the input to the
--- engine, not an answer.
---
--- Columns are 1-based to match the engine's own convention.
---@param root string
---@param name string
---@param langs table<string, boolean> extensions worth searching
---@param cb fun(candidates: table[])
function M.candidates(root, name, langs, cb)
  local args = { "rg", "--vimgrep", "--word-regexp", "--fixed-strings", name }
  for ext in pairs(langs) do
    args[#args + 1] = "-g"
    args[#args + 1] = "*." .. ext
  end
  vim.system(args, { cwd = root, text = true }, function(res)
    local out = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local path, lnum, col = line:match("^(.-):(%d+):(%d+):")
      if path then
        out[#out + 1] = { path = path, lnum = tonumber(lnum), col = tonumber(col) }
      end
    end
    cb(out)
  end)
end

--- The CALLERS of a definition: every place that genuinely binds to it.
---
--- Inbound. This answers "who uses this", which is what :ScryReach on a def
--- reports. It is NOT a footprint — see M.reaches for the other direction,
--- and the difference is not a nuance: an entry point nobody calls has no
--- callers and a large footprint, which is exactly what an entry point is.
---
--- The shape is the answer AND its provenance. `resolved` says an engine
--- decided each of these; without one, `n` is a count of mentions and the
--- caller has to render it as such. Conflating the two is the whole failure
--- this guards against — a name match is not a reference.
---@param root string
---@param target { path: string, lnum: integer, name: string }
---@param cb fun(r: { n: integer, files: integer, resolved: boolean, hits: table[] })
function M.callers(root, target, cb)
  local lang = M.lang_of(target.path)
  local exts = {}
  for ext, l in pairs(EXT_LANG) do
    if l == lang then
      exts[ext] = true
    end
  end
  if not next(exts) then
    exts[(target.path:match("%.([%w]+)$") or "")] = true
  end

  local function shape(hits, resolved)
    local files, n = {}, 0
    for _, h in ipairs(hits) do
      if not files[h.path] then
        files[h.path] = true
        n = n + 1
      end
    end
    return { n = #hits, files = n, resolved = resolved, hits = hits }
  end

  M.candidates(root, target.name, exts, function(cands)
    -- vim.schedule because everything below asks vim.fn where things are —
    -- the engine binary, the database — and a vim.system callback runs in a
    -- fast event context where vim.fn is forbidden. Without this the whole
    -- resolve step died inside libuv with a traceback nobody would connect
    -- to name resolution.
    vim.schedule(function()
      -- Drop the definition's own line: a definition does not reach itself.
      local refs = {}
      for _, c in ipairs(cands) do
        if not (c.path == target.path and c.lnum == target.lnum) then
          refs[#refs + 1] = c
        end
      end
      if not M.engine(lang) or #refs == 0 then
        cb(shape(refs, false))
        return
      end
      M.resolve(root, lang, refs, target, function(kept, err)
        -- An engine that errored degrades to the textual answer rather than
        -- to nothing, and says which it gave.
        cb(shape(kept or refs, kept ~= nil and err == nil))
      end)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- The cache, and why reach is stored at all
--
-- Reach is expensive: indexing a project is the slowest thing scry does. A
-- check has to stay cheap enough to run every time you look, so reach
-- cannot be part of one. But its ANSWER is exactly what |scry-divergence|
-- needs — a file a feature's entry points genuinely reach is described by
-- that feature, whether or not anyone listed it.
--
-- So the answer is written down, out of the repo alongside the run cache,
-- and divergence reads it. It carries a fingerprint of the files it was
-- computed from, because a stale reach is worse than none: it would keep a
-- file out of the unclaimed list on the strength of a binding that has
-- since been deleted.
-- ---------------------------------------------------------------------------

--- Cache file for a root. Machine-local, like runs — a resolved binding is
--- a fact about this checkout, not something to commit.
---@param root string
---@return string
--- Callers must be on the main loop: this uses vim.fn, which a vim.system
--- callback's fast event context forbids. of_feature schedules its own
--- continuation for exactly this reason.
function M.cache_path(root)
  local dir = vim.fn.stdpath("state") .. "/scry/reach"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(root, ":p"):gsub("[/\\:]", "%%") .. "json"
end

---@param root string
---@return table<string, { files: string[], at: integer, fingerprint: string }>
function M.cache_load(root)
  local f = io.open(M.cache_path(root), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  return (ok and type(decoded) == "table") and decoded or {}
end

---@param root string
---@param cache table
function M.cache_save(root, cache)
  local f = io.open(M.cache_path(root), "w")
  if f then
    f:write(vim.json.encode(cache))
    f:close()
  end
end

--- What a FILE reaches in one hop: the files its identifiers resolve into.
---
--- Outbound, and the opposite question from M.callers. Every identifier
--- position in the file is handed to the engine at once, and each
--- definition it resolves to that lives in another file is a dependency.
--- That is a footprint: the code behind an entry point, which is precisely
--- what nobody should have to enumerate by hand.
---
--- Identifiers come from ripgrep rather than a parser because the engine
--- discards anything that does not resolve — an over-broad candidate list
--- costs a little time and cannot produce a wrong answer.
---@param root string
---@param path string
---@param cb fun(files: string[], resolved: boolean)
function M.reaches(root, path, cb)
  local lang = M.lang_of(path)
  if not M.engine(lang) then
    cb({}, false)
    return
  end
  local db, real = M.db(root), vim.fn.resolve(vim.fn.fnamemodify(root, ":p"))
  local bin = M.engine(lang)
  vim.system({ "rg", "--vimgrep", "--only-matching", "[A-Za-z_][A-Za-z0-9_]*", path }, { cwd = root, text = true }, function(res)
    local args = { bin, "query", "-D", db, "definition" }
    local seen, n = {}, 0
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local p, l, c = line:match("^(.-):(%d+):(%d+):")
      -- Bounded: a position list is a command line, and a huge file would
      -- otherwise build one the OS refuses to run.
      if p and n < 400 then
        local key = l .. ":" .. c
        if not seen[key] then
          seen[key] = true
          n = n + 1
          args[#args + 1] = ("%s:%s:%s"):format(p, l, c)
        end
      end
    end
    if n == 0 then
      cb({}, true)
      return
    end
    vim.system(args, { cwd = root, text = true }, function(q)
      if q.code ~= 0 then
        cb({}, false)
        return
      end
      local files, out, any_resolved = {}, {}, false
      for _, ds in pairs(M.parse_query(q.stdout or "", root, real)) do
        for _, d in ipairs(ds) do
          any_resolved = true
          if d.path ~= path and not files[d.path] then
            files[d.path] = true
            out[#out + 1] = d.path
          end
        end
      end
      table.sort(out)
      -- A file where NOT ONE identifier resolves is a file the engine did
      -- not cover — an unindexed language, a grammar that choked. That is
      -- reported unresolved rather than as a confident zero.
      --
      -- It is a weak signal and worth being plain about: a file whose
      -- identifiers resolve only to ITSELF passes this test and still
      -- reaches nothing outside. That is observable on a real project,
      -- where an imported name resolves to its own import binding and the
      -- chain stops there rather than continuing into the imported file. A
      -- minimal fixture of the same shape does continue, so the difference
      -- is a property of that project or that grammar and is NOT explained
      -- here. What is not explained is not asserted.
      cb(out, any_resolved or n == 0)
    end)
  end)
end

--- A feature's whole footprint: everything its entry points reach,
--- transitively.
---
--- The defs are the entry points and this walks outward from them. Depth is
--- bounded because a footprint that reaches the whole repository tells you
--- nothing — and because each hop is a subprocess.
---@param root string
---@param feature scry.Feature
---@param cb fun(files: string[], resolved: boolean)
function M.of_feature(root, feature, cb)
  local frontier, seen, all_resolved = {}, {}, true
  for _, claim in ipairs(feature.claims) do
    local path = require("scry.map").claim_path(claim)
    if path and (claim.kind == "def" or claim.kind == "module") and not seen[path] then
      seen[path] = true
      frontier[#frontier + 1] = path
    end
  end
  if #frontier == 0 then
    cb({}, true)
    return
  end

  local DEPTH = 3
  local function hop(depth, current)
    if depth > DEPTH or #current == 0 then
      local out = {}
      for p in pairs(seen) do
        out[#out + 1] = p
      end
      table.sort(out)
      cb(out, all_resolved)
      return
    end
    local next_, left = {}, #current
    for _, path in ipairs(current) do
      M.reaches(root, path, function(files, ok)
        -- Only the FIRST hop decides whether an engine saw this feature.
        -- Deeper files are found BY resolution, so a leaf among them with
        -- nothing left to resolve is the normal end of a chain, not a blind
        -- spot — counting it would mark every complete walk unresolved.
        if not ok and depth == 1 then
          all_resolved = false
        end
        for _, f in ipairs(files) do
          if not seen[f] then
            seen[f] = true
            next_[#next_ + 1] = f
          end
        end
        left = left - 1
        if left == 0 then
          vim.schedule(function()
            hop(depth + 1, next_)
          end)
        end
      end)
    end
  end
  vim.schedule(function()
    hop(1, frontier)
  end)
end

--- A deterministic stamp for a set of files.
---
--- runs.fingerprint returns a TABLE, and comparing two tables with ~=
--- compares identities, so a cache guarded that way is never valid and
--- never used — the reach was computed, written, and then silently ignored
--- on every read. Sorted and flattened to a string, it compares by value.
---@param root string
---@param files string[]
---@return string
function M.stamp(root, files)
  local runs = require("scry.runs")
  local sorted = vim.deepcopy(files)
  table.sort(sorted)
  local parts = {}
  for _, p in ipairs(sorted) do
    parts[#parts + 1] = p .. "=" .. tostring(runs.mark(root, p))
  end
  return table.concat(parts, ";")
end

--- The reach recorded for a feature, or nil when there is none or it has
--- gone stale. Staleness is by fingerprint over the reached files: if any
--- of them changed, the binding that put them there may not exist any more,
--- and keeping a file out of the unclaimed list on a deleted binding is the
--- one failure a cache here can cause.
---@param root string
---@param feature_name string
---@return string[]?
function M.cached(root, feature_name)
  local entry = M.cache_load(root)[feature_name]
  if not entry or type(entry.files) ~= "table" then
    return nil
  end
  if entry.fingerprint ~= M.stamp(root, entry.files) then
    return nil
  end
  return entry.files
end

--- Index EVERY language in the project that has an engine, into the one
--- shared database, then run `after`.
---
--- Every language, not the one the entry point happens to be written in.
--- Real projects mix — the project this was built for has `.ts` pages over
--- `.js` libraries — and indexing only the caller's language leaves the
--- callee invisible, which reads exactly like the engine being unable to
--- resolve across the boundary. It is not; it was never asked.
---@param root string
---@param _lang string? ignored, kept so callers need not care
---@param after fun()
function M.with_index(root, _lang, after)
  local by_lang = {}
  local res = vim.system({ "rg", "--files" }, { cwd = root, text = true }):wait()
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local l = M.lang_of(line)
    if l and M.engine(l) then
      by_lang[l] = by_lang[l] or {}
      table.insert(by_lang[l], line)
    end
  end
  local langs = {}
  for l in pairs(by_lang) do
    langs[#langs + 1] = l
  end
  if #langs == 0 then
    after()
    return
  end
  vim.notify(("[scry] indexing %s for reach…"):format(table.concat(langs, ", ")))
  -- Sequential: they share one database, and two engines writing it at once
  -- is not a race worth discovering later.
  local i = 0
  local function step()
    i = i + 1
    if i > #langs then
      vim.schedule(after)
      return
    end
    M.index(root, langs[i], by_lang[langs[i]], function()
      vim.schedule(step)
    end)
  end
  step()
end

--- Compute and record a whole feature's reach.
---@param root string
---@param feature scry.Feature
function M.feature_show(root, feature)
  local lang
  for _, c in ipairs(feature.claims) do
    if c.kind == "def" then
      lang = lang or M.lang_of((c.target:match("^(.-):") or ""))
    end
  end
  M.with_index(root, lang, function()
    M.of_feature(root, feature, function(files, resolved)
      vim.schedule(function()
        if #files == 0 then
          vim.notify(("[scry] %s reaches nothing scry can see"):format(feature.name))
          return
        end
        -- Only a resolved answer is recorded. A name match must never
        -- excuse a file from the unclaimed list.
        if resolved then
          local cache = M.cache_load(root)
          cache[feature.name] = {
            files = files,
            at = os.time(),
            fingerprint = M.stamp(root, files),
          }
          M.cache_save(root, cache)
        end
        vim.notify(
          ("[scry] %s reaches %d file(s)%s"):format(
            feature.name,
            #files,
            resolved and " — recorded, and divergence will count them" or " — TEXT ONLY, not recorded"
          )
        )
      end)
    end)
  end)
end

--- :ScryReach — everything that binds to the def under the cursor, into the
--- quickfix list.
---
--- The quickfix list because that is where every list of places goes in
--- this family, and because quickfix-pro decorates it. The TITLE carries
--- the provenance: a reader has to be able to tell a resolved answer from a
--- textual one without remembering which engines are installed.
function M.show()
  local glass = require("scry.glass")
  local state = glass._state
  if not (state.buf and vim.api.nvim_get_current_buf() == state.buf and state.root) then
    vim.notify("[scry] :ScryReach works on a claim in the glass", vim.log.levels.WARN)
    return
  end
  local mapmod = require("scry.map")
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local map_ = mapmod.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), mapmod.kinds_for(state.root))
  local claim
  for _, c in ipairs(map_.claims) do
    if c.lnum == lnum then
      claim = c
    end
  end
  -- On a FEATURE line: the reach of everything it enters by, unioned and
  -- recorded, so divergence stops asking you to name files your entry
  -- points already reach.
  if not claim then
    local feature
    for _, f in ipairs(map_.features) do
      if f.lnum == lnum then
        feature = f
      end
    end
    if feature then
      M.feature_show(state.root, feature)
      return
    end
  end
  if not claim or claim.kind ~= "def" then
    vim.notify("[scry] reach is a question about a def or a feature", vim.log.levels.WARN)
    return
  end
  local path, name = claim.target:match("^(.-):([%w_.]+)$")
  if not path then
    vim.notify("[scry] " .. claim.target .. " names no symbol to trace", vim.log.levels.WARN)
    return
  end
  name = name:match("([%w_]+)$") or name

  local lang = M.lang_of(path)
  local target_lnum = require("scry.resolvers.ts_rg").locate(state.root, path, name) or 1

  local function report()
    M.of(state.root, { path = path, lnum = target_lnum, name = name }, function(r)
      vim.schedule(function()
        if r.n == 0 then
          vim.notify(("[scry] nothing reaches %s"):format(claim.target))
          return
        end
        local items = {}
        for _, h in ipairs(r.hits) do
          items[#items + 1] = { filename = h.path, lnum = h.lnum, col = h.col, text = name }
        end
        local how = r.resolved and "resolved" or "text only — no engine for " .. tostring(lang)
        vim.fn.setqflist({}, " ", {
          title = ("scry: reach of %s (%s)"):format(claim.target, how),
          items = items,
        })
        vim.notify(("[scry] %s: %d reference(s) in %d file(s) — %s — :copen"):format(claim.target, r.n, r.files, how))
      end)
    end)
  end

  M.with_index(state.root, lang, report)
end

--- A one-line account of what reach is available here, for :checkhealth.
---@return string[]
function M.status()
  local out = {}
  local seen = {}
  for lang, crate in pairs(ENGINE) do
    if not seen[crate] then
      seen[crate] = true
      local bin = M.engine(lang)
      out[#out + 1] = ("%s: %s"):format(crate, bin and ("provisioned (" .. bin .. ")") or "not provisioned — reach stays textual")
    end
  end
  table.sort(out)
  return out
end

return M
