-- Zero-config bootstrap: the commands exist without a setup() call, and
-- nothing heavy is required until one of them runs.
if vim.g.loaded_scry or vim.g.scry_disable then
  return
end
vim.g.loaded_scry = 1

require("scry")
