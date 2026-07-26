local M = {}

local data = {}

function M.put(key, value)
  data[key] = value
end

function M.get(key)
  return data[key]
end

function M.purge()
  data = {}
end

return M
