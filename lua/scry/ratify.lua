-- Ratification: an act that confers ownership by putting a name on a claim.
-- The stamp is "-- @user YYYY-MM-DD hex6" where hex6 is the head of
-- sha256(target). Staleness is mechanical and free: editing a claim's
-- target invalidates the hash, so an edited claim is unratified again —
-- no write hooks, no hidden state, and the stamp survives in git diffs.
--
-- A stamp is a record of intent, not authenticated attribution: @user is
-- whatever `git config user.name` says (or the config override).
local M = {}

--- The 6-hex ratification hash of a claim target.
---@param target string
---@return string
function M.hash(target)
  return vim.fn.sha256(target):sub(1, 6)
end

--- Is this claim ratified — stamped, and stamped for its CURRENT text?
---@param claim scry.Claim
---@return boolean
function M.ratified(claim)
  return claim.stamp ~= nil and claim.stamp.hash == M.hash(claim.target)
end

--- The ratifier's name: config override, else git user.name, else $USER.
---@param config table
---@return string
function M.author(config)
  if config.author and config.author ~= "" then
    return config.author
  end
  local git = vim.fn.systemlist({ "git", "config", "user.name" })[1]
  if git and git ~= "" then
    -- Parenthesized: gsub returns (string, count), and an extra return value
    -- here would be spread into the next argument at the call site.
    return (git:gsub("%s+", "-"))
  end
  return vim.env.USER or "someone"
end

--- Rewrite `claim`'s line in `map` with a fresh stamp. Returns the new line.
---@param map scry.Map
---@param claim scry.Claim
---@param author string
---@param date string? YYYY-MM-DD; defaults to today.
---@return string
function M.stamp(map, claim, author, date)
  -- Guard the shape rather than trusting callers: a stamp whose date fails
  -- STAMP_PAT reparses as part of the target, silently un-ratifying the
  -- claim it just stamped.
  if type(date) ~= "string" or not date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    date = os.date("%Y-%m-%d")
  end
  local line = ("    %s  -- @%s %s %s"):format(claim.target, author, date, M.hash(claim.target))
  map.lines[claim.lnum] = line
  claim.stamp = { user = author, date = date, hash = M.hash(claim.target) }
  return line
end

return M
