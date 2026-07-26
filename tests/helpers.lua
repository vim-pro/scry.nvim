-- Shared helpers for headless specs. Load with:
--   local H = dofile(vim.fn.fnamemodify(<spec path>, ":h") .. "/helpers.lua")
local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(H.root)

H.fixture = H.root .. "/tests/fixture"

function H.fail(msg)
  io.stderr:write("FAIL: " .. msg .. "\n")
  os.exit(1)
end

function H.eq(got, want, what)
  if got ~= want then
    H.fail(("%s: got %s, want %s"):format(what, vim.inspect(got), vim.inspect(want)))
  end
end

function H.ok(cond, what)
  if not cond then
    H.fail(what)
  end
end

--- Pump the loop until cond() or timeout; returns whether it settled.
function H.wait(cond, timeout)
  return vim.wait(timeout or 3000, cond, 10)
end

--- Read a file into a list of lines ("" for a missing file -> nil).
function H.read_lines(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

--- All virt_text chunks in `ns` on `buf`, concatenated per row: {[row]=text}.
function H.virt_by_row(buf, ns)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local parts = {}
    for _, chunk in ipairs(m[4].virt_text or {}) do
      parts[#parts + 1] = chunk[1]
    end
    for _, vline in ipairs(m[4].virt_lines or {}) do
      for _, chunk in ipairs(vline) do
        parts[#parts + 1] = chunk[1]
      end
    end
    if #parts > 0 then
      out[m[2]] = (out[m[2]] or "") .. table.concat(parts)
    end
  end
  return out
end

function H.done(msg)
  print(msg)
  os.exit(0)
end

return H
