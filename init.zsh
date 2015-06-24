#! /bin/zsh

wget -O ~/.zshrc http://git.grml.org/f/grml-etc-core/etc/zsh/zshrc

ln -sf ~/dotfiles/zshrc.local ~/.zshrc.local
ln -sf ~/dotfiles/vimrc ~/.vimrc
ln -sf ~/dotfiles/vim/bundle ~/.vim/bundle
