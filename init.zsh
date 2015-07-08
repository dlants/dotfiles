#! /bin/bash

# set up vundle
git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim

ln -sf ~/dotfiles/vimrc ~/.vimrc

vim +PluginInstall +qall

# ctrlp-cmatcher requires an install
bash -c "cd ~/.vim/bundle/ctrlp-cmatcher && CFLAGS=-Qunused-arguments CPPFLAGS=-Qunused-arguments ./install.sh"
