if vim.g.vscode then
    require "./init-vscode"
else
    require "./init-native"
end