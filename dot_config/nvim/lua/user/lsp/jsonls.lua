local M = {}

M.config = {
  filetypes = { 'json', 'jsonc' },

  on_attach = function(client)
    -- disable formatting for JSON; we'll use prettier through null-ls instead
    client.resolved_capabilities.document_formatting = false
  end,
}

local schemastore = require('user.req')('schemastore')
if schemastore then
  M.config.settings = {
    json = {
      schemas = vim.list_extend({
        {
          description = 'Deno configuration file',
          fileMatch = { 'deno*.json', 'deno*.jsonc' },
          url = 'https://raw.githubusercontent.com/denoland/deno/main/cli/schemas/config-file.v1.json',
        },
      }, schemastore.json.schemas()),
    },
  }
end

return M
