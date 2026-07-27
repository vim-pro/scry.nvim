-- Provenance: ownership inferred from the work, never performed as an act.
--
-- There is no "sign this" gesture anywhere in scry. Instead, the ordinary
-- actions of doing the work leave a trail per claim:
--
--   authored    you typed or edited the claim's text in the glass
--   conjured    you sent it to the conjurer
--   red/green   its spec failed, then passed, under your :ScryExercise
--   settled     a claim you cascaded came true on your save
--
-- A claim is OWNED when the trail shows a person passed through it:
-- authored, or conjured-and-it-came-true. Everything else renders ∅
-- untouched — which is precisely the state of machine-drafted inventory
-- nobody has engaged with.
--
-- Every event is keyed to a hash of the claim's text at the moment it was
-- recorded, so the old ratification property survives the redesign: edit a
-- claim and its trail is void, mechanically, no hooks.
local M = {}

--- Hash head that keys a trail to the claim text it described.
---@param claim scry.Claim
---@return string
function M.hash(claim)
  return vim.fn.sha256(claim.kind .. "\1" .. claim.target):sub(1, 8)
end

local function store_path(root)
  local dir = vim.fn.stdpath("state") .. "/scry/provenance"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(root, ":p"):gsub("[/\\:]", "%%") .. "json"
end

---@param root string
---@return table<string, table<string, boolean|string>>  claim_id -> {hash, events...}
function M.load(root)
  local f = io.open(store_path(root), "r")
  if not f then
    return {}
  end
  local ok, t = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return (ok and type(t) == "table") and t or {}
end

local function save(root, t)
  local f = io.open(store_path(root), "w")
  if f then
    f:write(vim.json.encode(t))
    f:close()
  end
end

--- Record one event on a claim's trail. A hash mismatch (the claim's text
--- changed since the last event) voids the old trail first.
---@param root string
---@param claim scry.Claim
---@param event "authored"|"conjured"|"red"|"green"|"settled"
function M.record(root, claim, event)
  local mapmod = require("scry.map")
  local t = M.load(root)
  local id = mapmod.claim_id(claim)
  local h = M.hash(claim)
  local trail = t[id]
  if not trail or trail.hash ~= h then
    trail = { hash = h }
  end
  trail[event] = true
  t[id] = trail
  save(root, t)
end

--- The inference. No event may be older than the claim's current text.
---@param root string
---@param claim scry.Claim
---@return boolean
function M.owned(root, claim)
  local trail = M.load(root)[require("scry.map").claim_id(claim)]
  if not trail or trail.hash ~= M.hash(claim) then
    return false
  end
  if trail.authored then
    return true
  end
  -- conjured, and it came true under your hands
  return (trail.conjured and (trail.settled or trail.green)) and true or false
end

--- Called after every check: convert state transitions into events. A claim
--- you conjured that is now backed has settled — no one needs to say so.
---@param root string
---@param map_ scry.Map
---@param report scry.Report
function M.sync(root, map_, report)
  local mapmod = require("scry.map")
  local t = M.load(root)
  local dirty = false
  for _, claim in ipairs(map_.claims) do
    local trail = t[mapmod.claim_id(claim)]
    if trail and trail.hash == M.hash(claim) and trail.conjured and not trail.settled then
      local v = report.verdicts[mapmod.claim_id(claim)]
      if v and (v.status == "backed" or v.status == "clean") then
        trail.settled = true
        dirty = true
      end
    end
  end
  if dirty then
    save(root, t)
  end
end

--- Watch the glass buffer: claims that appear or change under the user's own
--- edits are AUTHORED. scry's own writes never pass through here — the
--- watcher compares against the snapshot the renderer keeps, and the
--- renderer updates that snapshot on its own writes first.
---@param buf integer
---@param root fun(): string
---@param snapshot fun(): scry.Map?  the last map scry itself rendered/wrote
function M.watch(buf, root, snapshot)
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    buffer = buf,
    callback = function()
      local mapmod = require("scry.map")
      local prev = snapshot()
      if not prev then
        return
      end
      local before = {}
      for _, c in ipairs(prev.claims) do
        before[mapmod.claim_id(c)] = true
      end
      local now = mapmod.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      for _, c in ipairs(now.claims) do
        if not before[mapmod.claim_id(c)] then
          M.record(root(), c, "authored")
        end
      end
    end,
  })
end

return M
