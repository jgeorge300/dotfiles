local modbase = ...
local util = require('user.util')
local req = require('user.req')

local lspconfig = req('lspconfig')
if not lspconfig then
  return
end

-- load the config for a given client, if it exists
local function load_client_config(server_name)
  local status, client_config = pcall(require, modbase .. '.' .. server_name)
  if not status or type(client_config) ~= 'table' then
    return {}
  end
  return client_config
end

local M = {}

M.config = function()
  -- give LspInfo windows a border
  local lspconfig_win = require('lspconfig.ui.windows')
  local default_win_opts = lspconfig_win.default_opts
  lspconfig_win.default_opts = function(options)
    local opts = default_win_opts(options)
    opts.border = 'rounded'
    return opts
  end

  -- UI
  vim.fn.sign_define(
    'DiagnosticSignError',
    { text = '', texthl = 'DiagnosticSignError' }
  )
  vim.fn.sign_define(
    'DiagnosticSignWarn',
    { text = '', texthl = 'DiagnosticSignWarn' }
  )
  vim.fn.sign_define(
    'DiagnosticSignInfo',
    { text = '', texthl = 'DiagnosticSignInfo' }
  )
  vim.fn.sign_define(
    'DiagnosticSignHint',
    { text = '', texthl = 'DiagnosticSignHint' }
  )

  local lsp = vim.lsp

  lsp.handlers['textDocument/publishDiagnostics'] = lsp.with(
    lsp.handlers['textDocument/publishDiagnostics'],
    { virtual_text = false }
  )

  lsp.handlers['textDocument/hover'] = lsp.with(
    lsp.handlers.hover,
    { border = 'rounded' }
  )

  lsp.handlers['textDocument/signatureHelp'] = lsp.with(
    lsp.handlers.signature_help,
    { border = 'rounded' }
  )

  -- wrap lsp.buf_attach_client to allow clients to determine whether they should
  -- actually be attached
  local orig_buf_attach_client = lsp.buf_attach_client
  function lsp.buf_attach_client(bufnr, client_id)
    local client = lsp.get_client_by_id(client_id)
    if
      not client.config.should_attach or client.config.should_attach(bufnr)
    then
      return orig_buf_attach_client(bufnr, client_id)
    end
  end
end

-- configure a client when it's attached to a buffer
M.on_attach = function(client, bufnr)
  local opts = { buffer = bufnr }

  pcall(function()
    require('illuminate').on_attach(client)
  end)

  pcall(function()
    require('lsp_signature').on_attach({ max_width = 80 })
  end)

  -- perform general setup

  if client.resolved_capabilities.goto_definition then
    util.nmap('<C-]>', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
  end

  if client.resolved_capabilities.hover then
    util.map('K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
  end

  if client.resolved_capabilities.rename then
    util.lmap('r', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
  end

  if client.resolved_capabilities.document_formatting then
    util.bufcmd('Format', 'lua require("user.lsp").format_sync()')
    util.lmap('F', '<cmd>Format<cr>', opts)
    -- vim.cmd(
    --   'autocmd BufWritePre <buffer> lua require("user.lsp").autoformat_sync()'
    -- )
  end

  if not packer_plugins['trouble.nvim'] then
    util.lmap('e', '<cmd>lua vim.lsp.diagnostic.set_loclist()<cr>', opts)
  end

  util.lmap(
    'd',
    '<cmd>lua require("user.lsp").show_position_diagnostics()<cr>',
    opts
  )
end

-- auto-format the current buffer, but exclude certain cases
M.autoformat_sync = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)

  -- don't autoformat ignored code
  local response = vim.fn.system({ 'git', 'is-ignored', name })
  if response == '1' then
    return
  end

  -- don't autoformat library code
  if
    name:find('/node_modules/')
    or name:find('/__pypackages__/')
    or name:find('/site_packages/')
  then
    return
  end

  M.format_sync()
end

-- format the current buffer, handling the case where multiple formatters are
-- present
M.format_sync = function()
  local clients = vim.tbl_values(vim.lsp.buf_get_clients())
  local formatters = vim.tbl_filter(function(client)
    return client.supports_method('textDocument/formatting')
  end, clients)

  local formatter
  if #formatters == 0 then
    return
  end

  if #formatters == 1 then
    formatter = formatters[1]
  else
    local non_null_ls = vim.tbl_filter(function(client)
      return client.name ~= 'null-ls'
    end, formatters)
    formatter = non_null_ls[1]
  end

  local params = vim.lsp.util.make_formatting_params(nil)
  local bufnr = vim.api.nvim_get_current_buf()
  local result, err = formatter.request_sync(
    'textDocument/formatting',
    params,
    5000,
    bufnr
  )
  if result and result.result then
    vim.lsp.util.apply_text_edits(
      result.result,
      bufnr,
      formatter.offset_encoding
    )
  elseif err then
    vim.notify('vim.lsp.buf.formatting_sync: ' .. err, vim.log.levels.WARN)
  end
end

-- style the line diagnostics popup
M.show_position_diagnostics = function()
  vim.diagnostic.open_float(0, {
    scope = 'cursor',
    border = 'rounded',
    max_width = 80,
    show_header = false,
    focusable = false,
  })
end

-- setup a server
M.get_lsp_config = function(server)
  -- default config for all servers
  local config = {}

  -- add server-specific config if applicable
  local client_config = load_client_config(server)
  if client_config.config then
    config = vim.tbl_deep_extend('force', config, client_config.config)
  end

  if config.on_attach then
    local config_on_attach = config.on_attach
    config.on_attach = function(client, bufnr)
      config_on_attach(client, bufnr)
      M.on_attach(client, bufnr)
    end
  else
    config.on_attach = M.on_attach
  end

  -- add cmp capabilities
  local cmp = require('cmp_nvim_lsp')
  config.capabilities = cmp.update_capabilities(
    vim.lsp.protocol.make_client_capabilities()
  )

  return config
end

return M
