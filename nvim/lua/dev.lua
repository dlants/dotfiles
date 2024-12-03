vim.keymap.set('n', '<leader>pr', function()
  package.loaded['magenta'] = nil
  require('magenta')
  print 'magenta reloaded'
end, { desc = 'Reload magenta plugin' })

_G.P = function(v)
  print(vim.inspect(v))
  return v
end

vim.keymap.set('n', '<leader>t', function()
  local plenary = require('plenary.test_harness')
  plenary.test_directory(vim.fn.expand('%:p'))
end, { desc = 'Run plenary test under cursor' })
