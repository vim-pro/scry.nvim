local M = {}

function M.debug(msg)
  io.stderr:write(msg .. "\n")
end

return M
