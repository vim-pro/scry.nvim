local M = {}

local store = require("store")
local logging = require("logging")

function M.create_session(user)
  local token = tostring(math.random(1e9))
  store.put(token, user)
  logging.debug("session created for " .. user)
  return token
end

function M.validate_token(raw)
  return store.get(raw) ~= nil
end

return M
