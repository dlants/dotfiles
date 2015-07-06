#! /bin/zsh

# set up vundle
git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim

# grml zsh config
wget -O ~/.zshrc http://git.grml.org/f/grml-etc-core/etc/zsh/zshrc

ln -sf ~/dotfiles/zshrc.local ~/.zshrc.local
ln -sf ~/dotfiles/vimrc ~/.vimrc

vim +PluginInstall +qall

cd ~/.vim/bundle/ctrlp-cmatcher
CFLAGS=-Qunused-arguments CPPFLAGS=-Qunused-arguments ./install.sh
