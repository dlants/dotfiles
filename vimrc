call plug#begin('~/.vim/plugged')
set nocompatible " be iMproved, required
filetype off     " required
set t_Co=256
set shell=/bin/bash

" completion
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
" Plug 'Shougo/echodoc.vim'
" Plug 'Shougo/neoinclude.vim' " <- deoplete source for relative / project files
" Plug 'roxma/nvim-completion-manager'

" files / navigation
Plug 'jremmen/vim-ripgrep'

" fzf installed through homebrew, to use it with shell commands as well
set rtp+=/usr/local/opt/fzf
Plug 'junegunn/fzf.vim'

" tmux
Plug 'christoomey/vim-tmux-navigator'
" Plug 'benmills/vimux'

" show errors
Plug 'vim-syntastic/syntastic', {'for': ['purescript', 'idris']}
Plug 'neomake/neomake'

" status line
Plug 'bling/vim-airline'

" pretty colors
Plug 'nanotech/jellybeans.vim'

" trim whitespace on save
Plug 'ntpeters/vim-better-whitespace'
"Plug 'Valloric/YouCompleteMe', {'do': './install.py'}

" git
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rhubarb'

" vim enhancements (motion, repeatability)
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-abolish'
Plug 'tpope/vim-endwise'
Plug 'tpope/vim-repeat'

" extra objects
Plug 'tpope/vim-surround' " work on surrounding parens, quotes, tags
Plug 'michaeljsmith/vim-indent-object' " work with indentation levels
Plug 'wellle/targets.vim' " separators, arguments

" jump around
Plug 'easymotion/vim-easymotion'

" language support
Plug 'dag/vim-fish'
Plug 'ElmCast/elm-vim', {'for': 'elm'}

" idris
Plug 'idris-hackers/idris-vim', {'for': 'idris'}

" purescript
Plug 'raichoo/purescript-vim', {'for': 'purescript'}
Plug 'frigoeu/psc-ide-vim', {'for': 'purescript'}
"Plug 'coot/psc-ide-vim', {'branch': 'sync-purescript-0.11'}

" Plug 'let-def/ocp-indent-vim'
Plug 'bitc/vim-hdevtools', {'for': 'haskell'}
Plug 'itchyny/vim-haskell-indent', {'for': 'haskell'}
Plug 'eagletmt/neco-ghc', {'for': 'haskell'}

" language protocol support - covers typescript
" Plug 'autozimu/LanguageClient-neovim', { 'do': ':UpdateRemotePlugins' }

" typescript
Plug 'leafgarland/typescript-vim', {'for': 'typescript'} " ts syntax highlighting
" Plug 'HerringtonDarkholme/yats.vim'
Plug 'ianks/vim-tsx' " tsx syntax highlighting
" Plug 'Quramy/tsuquyomi'
Plug 'Quramy/vim-js-pretty-template'
" Plug 'jason0x43/vim-js-indent' " better indentation
Plug 'jason0x43/vim-tss', {'for': 'typescript', 'do': 'npm install' } " code navigation, error reporting (+ neomake)
Plug 'mhartington/nvim-typescript', {'for': 'typescript', 'do': ':UpdateRemotePlugins' } " deoplete source

"Plug 'neovim/node-host', { 'branch': 'next'} " , 'do': 'npm install -g neovim@next' }
"Plug 'neovim/node-host', {'do': 'npm install'}
"Plug 'dlants/ts-neovim-ts', {'for': 'typescript', 'do': 'npm install; :UpdateRemotePlugins'}

" Plug 'runoshun/tscompletejob'

" js
Plug 'pangloss/vim-javascript'
Plug 'mtscout6/vim-cjsx'
Plug 'wavded/vim-stylus'
Plug 'kchmck/vim-coffee-script'
Plug 'elzr/vim-json'
Plug 'digitaltoad/vim-jade', {'for': 'pug'}

" racket
Plug 'wlangstroth/vim-racket', {'for': 'racket'}
call plug#end()

filetype plugin indent on " required
" ---------- Other config ------------
" basics
let mapleader = " "
let maplocalleader = "\\"
syntax enable
set synmaxcol=200

"au BufNewFile,BufRead *.es6 setf javascript.jsx
au BufNewFile,BufRead *.jade setf pug
au BufNewFile,BufRead *.re setf reason

set background=dark
set nowrap
set number
set relativenumber
set cursorline
set cursorcolumn
set colorcolumn=120
set noshowmode

" change highlight colors

" default register is clipboard
set clipboard=unnamed

" tabs and spaces!
set tabstop=2
set shiftwidth=2
set softtabstop=0
set expandtab

" faster pane resize
" noshift resizes vertically
nnoremap <leader>= :resize +5<CR>
nnoremap <leader>- :resize -5<CR>
" with shift resizes horizontally
nnoremap <leader>+ :vertical resize +5<CR>
nnoremap <leader>_ :vertical resize -5<CR>

" vimux (vim + tmux)
" open in a horizontal split ( like | )
" let g:VimuxOrientation = "h"
" let g:VimuxHeight = "50"


" opens a tmux split and opens ranger (for manipulating files)
" nnoremap <leader>tr :call VimuxRunCommandInDir("ranger", 0)<CR>

" open a tmux pane and run zsh
" nnoremap <leader>tz :VimuxRunCommand("zsh")<CR>

" send stuff to tmux pane
" function! VimuxSlime()
" call VimuxSendText(@v)
" call VimuxSendKeys("Enter")
" endfunction

" If text is selected, save it in the v buffer and send that buffer it to tmux
" vmap <LocalLeader>vs "vy :call VimuxSlime()<CR>

" Select current paragraph and send it to tmux
" nmap <LocalLeader>vs vip<LocalLeader>vs<CR>

" [] followed by j to jump forward or back in history
nnoremap [j <C-O>
nnoremap ]j <C-I>

" quickfix always takes up full width
au FileType qf wincmd J

" search
set ignorecase
set smartcase
set incsearch
set hlsearch

" python support
let g:python_host_prog = '/usr/bin/python2.7'
let g:python3_host_prog = '/Library/Frameworks/Python.framework/Versions/3.5/bin/python3.5'

" ncm
set shortmess+=c " don't show completion messages

" deoplete + echodoc
let g:deoplete#enable_at_startup = 1
let g:deoplete#enable_smart_case = 1
let g:deoplete#enable_camel_case = 1
let g:deoplete#file#enable_buffer_path = 1
"
let g:deoplete#omni#input_patterns = {}
let g:deoplete#omni#input_patterns.default = '\h\w*'

" don't pop up the preview window
set completeopt-=preview
"let g:deoplete#omni#input_patterns.purescript = '[^. *\t]'
autocmd CompleteDone * pclose!

" neomake
" let g:neomake_verbose = 3
autocmd! BufWritePost * Neomake

inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"

" syntastic recommended
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" fzf
" position
let g:fzf_layout = {'up': '~50%'}
nnoremap <leader>p :GFiles<CR>
nnoremap <leader>o :Files<CR>

" Mapping selecting mappings
nmap <leader><tab> <plug>(fzf-maps-n)
xmap <leader><tab> <plug>(fzf-maps-x)
omap <leader><tab> <plug>(fzf-maps-o)

" Insert mode completion
imap <c-x><c-k> <plug>(fzf-complete-word)
imap <c-x><c-f> <plug>(fzf-complete-path)
imap <c-x><c-j> <plug>(fzf-complete-file-ag)
imap <c-x><c-l> <plug>(fzf-complete-line)

" Rg
let g:rg_highlight = 1
let g:rg_derive_root = 1

" javascript
let g:jsx_ext_required = 0 " allow jsx in all files

" typescript
" disable maker for typescript -- we use nvim-typescript for this
let g:neomake_typescript_enabled_makers = []
" let g:typescript_indent_disable = 1

" run TSSyncErr on write
autocmd! BufWritePost *.ts,*.tsx TSSyncErr

"autocmd FileType typescript nmap <buffer> <Leader>t :TssQuickInfo<CR>
autocmd FileType typescript nmap <buffer> <Leader>n :TSRename<CR>
"autocmd FileType typescript nmap <buffer> <Leader>d :TssDefinition<CR>
"autocmd FileType typescript nmap <buffer> <Leader>R :TssReferences<CR>
autocmd FileType typescript nmap <buffer> <Leader>f :TssFormat<CR>

autocmd FileType typescript nmap <buffer> <Leader>t :TSType<CR>
autocmd FileType typescript nmap <buffer> <Leader>T :TSDoc<CR>
autocmd FileType typescript nmap <buffer> <Leader>d :TSDef<CR>
autocmd FileType typescript nmap <buffer> <Leader>D :TSTypeDef<CR>
autocmd FileType typescript nmap <buffer> <Leader>r :TSRefs<CR>

" elm-vim
" formatd elm on save
let g:elm_jump_to_error = 1
let g:elm_format_autosave = 1
let g:elm_detailed_complete = 1
let g:elm_setup_keybindings = 1
" let g:elm_syntastic_show_warnings = 1

" psc-ide-vim
" syntastic support disabled - let neomake do its thing
let g:psc_ide_syntastic_mode = 0
" let g:psc_ide_log_level = 3
"let g:neomake_purescript_enabled_makers = []

au FileType purescript nmap <leader>b :!pulp build<CR>
" au FileType purescript nmap <leader>e :Neomake<CR>
au FileType purescript nmap <leader>i :sp<CR>:terminal<CR>psci<CR>
au FileType purescript nmap <leader>t :Ptype<CR>
au FileType purescript nmap <leader>s :Papply<CR>
au FileType purescript nmap <leader>a :PaddType<CR>
au FileType purescript nmap <leader>c :PaddClause<CR>
au FileType purescript nmap <leader>d :Pgoto<CR>
au FileType purescript nmap <leader>m :Pimport<CR>

" better whitespace
" strip whitespace on save
autocmd BufWritePre * StripWhitespace

" load colorscheme last...
colorscheme jellybeans

" neovim stuff
" faster esc
" set esckeys
set nottimeout

" something was overriding escape ... wtf
nnoremap <Esc> <Esc>
nnoremap - -


" nvim-typescript debugging
" let g:deoplete#enable_debug = 1
" let g:deoplete#enable_profile = 1
" call deoplete#enable_logging('DEBUG', '/tmp/deoplete.log')
