vim.keymap.set('n', '<leader>pr', function()
  vim.cmd('UpdateRemotePlugins')
  vim.cmd('runtime plugin/magenta.vim')
end, { desc = 'Reload magenta plugin' })

_G.P = function(v)
  print(vim.inspect(v))
  return v
end

vim.keymap.set('n', '<leader>t', function()
  local plenary = require('plenary.test_harness')
  plenary.test_directory(vim.fn.expand('%:p'))
end, { desc = 'Run plenary test under cursor' })
