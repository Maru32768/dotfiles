set ignorecase                   " 検索時に大文字小文字を区別しない
set smartcase                    " 検索時に大文字を入力した場合,大文字小文字を区別する
set clipboard+=unnamed           " 無名レジスタに入るデータを*レジスタにも入れる
set number                       " 行番号を表示
set relativenumber               " 行番号を相対値に
set history=200
set showcmd
set vim-paragraph-motion

sethandler <c-o> a:vim n:ide
sethandler <c-i> a:vim n:ide
sethandler <c-q> a:vim
sethandler <c-y> a:vim
sethandler <c-c> a:vim
sethandler <c-v> a:vim

" nnoremap <c-o> :<c-u>action Back<cr>
" nnoremap <c-i> :<c-u>action Forward<cr>
" nnoremap [g :<c-u>action GotoPreviousError<cr>
" nnoremap ]g :<c-u>action GotoNextError<cr>
" nnoremap <leader>k :<c-u>action QuickJavaDoc<cr>
" nnoremap <c-q> :<c-u>action QuickJavaDoc<cr>
" nnoremap <leader>d :<c-u>action GotoDeclaration<cr>
" nnoremap <leader>f :<c-u>action GotoTypeDeclaration<cr>
" nnoremap <leader>i :<c-u>action GotoImplementation<cr>
nnoremap <leader>s :<c-u>action GotoSuperMethod<cr>
" nnoremap <leader>n :<c-u>action RenameElement<cr>
" nnoremap <c-n> :NERDTree<cr>
" nnoremap <c-p> :<c-u>action GotoFile<cr>

noremap <c-h> <c-w><c-h>
noremap <c-j> <c-w><c-j>
noremap <c-k> <c-w><c-k>
noremap <c-l> <c-w><c-l>
noremap <c-w><c-h> <c-h>H
noremap <c-w><c-j> <c-w>J
noremap <c-w><c-k> <c-w>K
noremap <c-w><c-l> <c-w>L

nnoremap j gj
nnoremap k gk
nnoremap GT gT
nnoremap GG G

inoremap <c-h> <left>
inoremap <c-j> <down>
inoremap <c-k> <up>
inoremap <c-l> <right>

noremap <silent> <leader>w :w<cr>
nnoremap * *N
nnoremap U <c-r>
nnoremap <silent> <esc><esc> :noh<cr>
nnoremap <silent> <c-[><c-[> :noh<cr>
nnoremap ; :
nnoremap : ;
nnoremap H ^
nnoremap L $
vnoremap H ^
vnoremap L $
inoremap <c-d> <del>
vnoremap , <esc>ggVG
nnoremap <c-w>q :q<cr>
nnoremap S ddO

" カーソル下の単語をハイライトしてから置換
nnoremap # "zyiw:let @z = '\<' . @z . '\>'<cr>:set hlsearch<cr>:%s/<c-r>z//g<left><left>

" 行を移動
nnoremap <c-up> "zdd<up>"zP
nnoremap <c-down> "zdd"zp
vnoremap <c-up> "zx<up>"zP`[V`]
vnoremap <c-down> "zx"zp`[V`]

inoremap <c-t> <esc><left>"zx"zpa

cnoremap <c-p> <up>
cnoremap <c-n> <down>
cnoremap <c-a> <home>
cnoremap <c-e> <end>
cnoremap <c-b> <left>
cnoremap <c-f> <right>
cnoremap <c-y> <c-r>"
