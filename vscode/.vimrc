set ignorecase                   " 検索時に大文字小文字を区別しない
set smartcase                    " 検索時に大文字を入力した場合,大文字小文字を区別する
set clipboard+=unnamed           " 無名レジスタに入るデータを*レジスタにも入れる
set number                       " 行番号を表示
set relativenumber               " 行番号を相対値に
set history=200
set showcmd
set vim-paragraph-motion

" nnoremap <leader>s :<c-u>action GotoSuperMethod<cr>

nnoremap w <leader>w
nnoremap e <leader>e
nnoremap b <leader>b
omap <silent> iw i<leader>w
xmap <silent> iw i<leader>w
omap <silent> ie i<leader>e
xmap <silent> ie i<leader>e
omap <silent> ib i<leader>b
xmap <silent> ib i<leader>b

noremap <c-h> <c-w><c-h>
noremap <c-j> <c-w><c-j>
noremap <c-k> <c-w><c-k>
noremap <c-l> <c-w><c-l>
noremap <c-w><c-h> <c-h>H
noremap <c-w><c-j> <c-w>J
noremap <c-w><c-k> <c-w>K
noremap <c-w><c-l> <c-w>L

nnoremap GT gT
nnoremap GG G

inoremap <c-h> <left>
inoremap <c-j> <down>
inoremap <c-k> <up>
inoremap <c-l> <right>

nnoremap <silent> <leader>w :w<cr>
nnoremap * *N
nnoremap U <c-r>
nnoremap <silent> <esc><esc> :noh<cr>
nnoremap <silent> <c-[><c-[> :noh<cr>
nnoremap ; :
nnoremap : ;
vnoremap ; :
vnoremap : ;
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
