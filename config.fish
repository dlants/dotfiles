if status is-interactive
    # Commands to run in interactive sessions can go here
end

if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end

alias vi nvim

# Enable vi keybindings
fish_vi_key_bindings
