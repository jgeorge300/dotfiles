#vim.loader.enable()

require('user.config.options')
require('user.config.filetypes')
require('user.config.lazy')
require('user.config.update')
require('user.config.keymaps')
require('user.config.autocommands')

vim.api.nvim_command('colorscheme wezterm')
