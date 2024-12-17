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

function DebugExtmarks(namespace)
    local ns = type(namespace) == "string"
        and vim.api.nvim_create_namespace(namespace)
        or namespace

    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
    for _, mark in ipairs(marks) do
        local id, row, col = unpack(mark)
        vim.api.nvim_buf_set_extmark(0, ns, row, col, {
            virt_text = {{string.format("[mark %d]", id), "Comment"}},
            virt_text_pos = "inline"
        })
    end
end
