set shell=/bin/bash
set nocompatible " be iMproved, required
filetype off     " required
set t_Co=256

" set the runtime path to include vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" let Vundle manage Vundle, required
Plugin 'gmarick/Vundle.vim'

" Vundle plugins
Plugin 'JazzCore/ctrlp-cmatcher'
Plugin 'kien/ctrlp.vim'
Plugin 'scrooloose/nerdtree'
Plugin 'scrooloose/syntastic'
Plugin 'mtscout6/vim-cjsx'
Plugin 'wavded/vim-stylus'
Plugin 'kchmck/vim-coffee-script'
Plugin 'tpope/vim-fugitive'
Plugin 'airblade/vim-gitgutter'
Plugin 'nathanaelkane/vim-indent-guides'
Plugin 'digitaltoad/vim-jade'
Plugin 'pangloss/vim-javascript'
Plugin 'elzr/vim-json'
Plugin 'mxw/vim-jsx'
Plugin 'tpope/vim-sensible'
Plugin 'tpope/vim-unimpaired'
Plugin 'bling/vim-airline'
Plugin 'ervandew/supertab'
Plugin 'yosiat/oceanic-next-vim'
Plugin 'nanotech/jellybeans.vim'

" Run `vim +PluginInstall +qall` if this list updates
call vundle#end() " required
filetype plugin indent on " required
" ---------- Other config ------------
" basics
syntax enable

au BufNewFile,BufRead *.babel setf javascript
au BufNewFile,BufRead *.es6 setf javascript

set background=dark
set nowrap
set number
set cursorline
set cursorcolumn

" change highlight colors

" default register is clipboard
set clipboard=unnamed

" tabs and spaces!
set tabstop=2
set shiftwidth=2
set softtabstop=0
set expandtab

" more natural pane swapping
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" faster pane resize
" noshift resizes vertically
nnoremap = :resize +5<CR>
nnoremap - :resize -5<CR>
" with shift resizes horizontally
nnoremap + :vertical resize +5<CR>
nnoremap _ :vertical resize -5<CR>

" search
set ignorecase
set smartcase
set incsearch
set hlsearch

" airline
let g:airline_powerline_fonts = 0

if executable('ag')
  " Use ag over grep
  " set grepprg=ag\ --nogroup\ --nocolor

  " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
  let g:ctrlp_user_command = 'ag %s -l --nocolor -g ""'

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0
endif

" more CtrlP options
let g:ctrlp_match_window = 'top,order:ttb,min:1,max:100'
let g:ctrlp_open_multiple_files='ri'
let g:ctrlp_working_path_mode = ''
let g:ctrlp_match_func = {'match' : 'matcher#cmatch'}

" nerdtree
map <C-n> :NERDTreeToggle<CR>

" indentGuides plugin
let g:indent_guides_enable_on_vim_startup=1
let g:indent_guides_auto_colors=0
hi IndentGuidesOdd ctermbg=black

" syntastic
" let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_coffee_checkers = ["coffeelint"]
let g:syntastic_coffee_coffeelint_args = "--csv --file ~/src/pillow/.coffeelint.json"
let g:jsx_ext_required = 0 " Allow JSX in normal JS files

" load colorscheme last...
colorscheme jellybeans
