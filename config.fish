if status is-interactive
    # Commands to run in interactive sessions can go here
    fish_vi_key_bindings
end

if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end

function fish_title
  echo "Your Custom Title"
end