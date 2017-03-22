call plug#begin('~/.vim/plugged')
set nocompatible " be iMproved, required
filetype off     " required
set t_Co=256

" plugins
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'Shougo/echodoc.vim'
"Plug 'Valloric/YouCompleteMe', {'do': './install.py'}
Plug 'Shougo/vimproc.vim', {'do': 'make'}
"Plug 'Shougo/denite.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdtree', {'on': 'NERDTreeToggle'}
Plug 'scrooloose/syntastic'
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-unimpaired'
Plug 'bling/vim-airline'
Plug 'tpope/vim-abolish'
Plug 'nanotech/jellybeans.vim'
Plug 'ntpeters/vim-better-whitespace'
Plug 'easymotion/vim-easymotion'

" language support
Plug 'dag/vim-fish'
Plug 'ElmCast/elm-vim', {'for': 'elm'}

" purescript
Plug 'raichoo/purescript-vim'
Plug 'frigoeu/psc-ide-vim'

" Plug 'let-def/ocp-indent-vim'
Plug 'bitc/vim-hdevtools'
Plug 'itchyny/vim-haskell-indent'
Plug 'eagletmt/neco-ghc'

" typescript
Plug 'leafgarland/typescript-vim'
Plug 'HerringtonDarkholme/yats.vim'
Plug 'Quramy/tsuquyomi'
Plug 'Quramy/vim-js-pretty-template'
Plug 'jason0x43/vim-js-indent'
Plug 'clausreinke/typescript-tools.vim'
Plug 'mhartington/nvim-typescript'

" js
Plug 'pangloss/vim-javascript'
Plug 'ianks/vim-tsx'
Plug 'mxw/vim-jsx'
Plug 'mtscout6/vim-cjsx'
Plug 'wavded/vim-stylus'
Plug 'kchmck/vim-coffee-script'
Plug 'elzr/vim-json'
Plug 'digitaltoad/vim-jade', {'for': 'pug'}
call plug#end()

filetype plugin indent on " required
" ---------- Other config ------------
" basics
let mapleader = " "
let maplocalleader = "\\"
syntax enable

"au BufNewFile,BufRead *.es6 setf javascript.jsx
au BufNewFile,BufRead *.jade setf pug
au BufNewFile,BufRead *.re setf reason

set background=dark
set nowrap
set number
set cursorline
set cursorcolumn
set colorcolumn=120
set completeopt-=preview
set noshowmode

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

" python support
let g:python_host_prog = '/usr/bin/python2.7'
let g:python3_host_prog = '/Library/Frameworks/Python.framework/Versions/3.5/bin/python3.5'

" deoplete + echodoc
let g:deoplete#enable_at_startup = 1
let g:deoplete#enable_smart_case = 1
let g:deoplete#enable_camel_case = 1
let g:echodoc_enable_at_startup = 1

let g:deoplete#omni#input_patterns = {}
let g:deoplete#omni#input_patterns.default = '\h\w*'
let g:deoplete#omni#input_patterns.purescript = '[^. *\t]'
autocmd CompleteDone * pclose!

" from https://github.com/Shougo/neocomplete.vim/issues/418
"if !exists('g:neocomplete#force_omni_input_patterns')
"    let g:neocomplete#force_omni_input_patterns = {}
"endif
"let g:neocomplete#force_omni_input_patterns.typescript = '[^. *\t]\.\w*\|\h\w*::'

inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
" fzf
" position
let g:fzf_layout = {'up': '~50%'}
map <C-O> :Files<CR>
map <C-P> :GFiles<CR>

" airline
let g:airline_powerline_fonts = 1

" nerdtree
map <C-n> :NERDTreeToggle<CR>

" indentGuides plugin
let g:indent_guides_enable_on_vim_startup=1
let g:indent_guides_auto_colors=0
hi IndentGuidesOdd ctermbg=black

" syntastic
" recommended
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
" leader + e shows errors
"nnoremap <Leader>e :Errors<CR>
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" other
let g:syntastic_echo_current_error = 1
let g:syntastic_cursor_column = 1
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_javascript_eslint_exec = './node_modules/.bin/eslint'
"let g:syntastic_javascript_eslint_args = '--file ~/src/pillow/.eslintrc.json'
let g:syntastic_coffee_checkers = ['coffeelint']
let g:syntastic_coffee_coffeelint_args = '--reporter csv --file ~/src/pillow/.coffeelint.json'
let g:syntastic_mode_map = { "passive_filetypes": ["javascript"] }

" javascript
let g:jsx_ext_required = 0 " allow jsx in all files
"autocmd FileType javascript.jsx :let b:syntastic_mode='active'

" typescript
let g:tsuquyomi_disable_quickfix = 1
let g:syntastic_typescript_checkers = ['tsuquyomi']

autocmd FileType typescript nmap <buffer> <Leader>h : <C-u>echo tsuquyomi#hint()<CR>
autocmd FileType typescript nmap <buffer> <Leader>t : <C-u>echo tsuquyomi#hint()<CR>
autocmd FileType typescript nmap <buffer> <Leader>r <Plug>(TsuquyomiRenameSymbol)
autocmd FileType typescript nmap <buffer> <Leader>d :TsuDefinition<CR>
autocmd FileType typescript nmap <buffer> <Leader>R <Plug>(TsuquyomiRenameSymbolC)
autocmd FileType typescript nmap <buffer> <Leader>m <Plug>(TsuquyomiImport)
autocmd FileType typescript nmap <buffer> <Leader>e :TsuquyomiGeterrProject<CR>

" haskell
autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc

" elm-vim
" format elm on save
let g:elm_jump_to_error = 1
let g:elm_format_autosave = 1
let g:elm_detailed_complete = 1
let g:elm_setup_keybindings = 1
let g:elm_syntastic_show_warnings = 1

" psc-ide-vim
" syntastic support
let g:psc_ide_syntastic_mode = 1
"let g:psc_ide_log_level = 3

au FileType purescript nmap <leader>b :!pulp build<CR>
au FileType purescript nmap <leader>r :!pulp run<CR>
au FileType purescript nmap <leader>e :ll<CR>
au FileType purescript nmap <leader>i :sp<CR>:terminal<CR>pulp psci<CR>
"au FileType purescript nmap <leader>i :sp<CR>:terminal<CR>pulp psci<CR>:load %
au FileType purescript nmap <leader>t :PSCIDEtype<CR>
au FileType purescript nmap <leader>s :PSCIDEapplySuggestion<CR>
au FileType purescript nmap <leader>a :PSCIDEaddTypeAnnotation<CR>
au FileType purescript nmap <leader>d :PSCIDEgoToDefinition<CR>
au FileType purescript nmap <leader>m :PSCIDEimportIdentifier<CR>
au FileType purescript nmap <leader>l :PSCIDEload<CR>
au FileType purescript nmap <leader>p :PSCIDEpursuit<CR>
au FileType purescript nmap <leader>c :PSCIDEcaseSplit<CR>
au FileType purescript nmap <leader>qd :PSCIDEremoveImportQualifications<CR>
au FileType purescript nmap <leader>qa :PSCIDEaddImportQualifications<CR>

" OCaml + merlin
" let s:ocamlmerlin=substitute(system('opam config var share'),'\n$','','') . "/merlin"
" execute "set rtp+=".s:ocamlmerlin."/vim"
" execute "set rtp+=".s:ocamlmerlin."/vimbufsync"
" let g:syntastic_ocaml_checkers=['merlin']
"
"" Reason plugin which uses Merlin
"let s:reasondir=substitute(system('opam config var share'),'\n$','','') . "/reason"
"execute "set rtp+=".s:reasondir."/editorSupport/VimReason"
"let g:syntastic_reason_checkers=['merlin']

" better whitespace
" strip whitespace on save
autocmd BufWritePre * StripWhitespace

" load colorscheme last...
colorscheme jellybeans

" neovim stuff
" faster esc
set esckeys
set nottimeout

" make esc leave input mode in terminal
":tnoremap <Esc> <C-\><C-n>
