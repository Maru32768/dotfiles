#!/bin/bash

rm ~/.vimrc
ln -s ~/dotfiles/vim/.vimrc ~/.vimrc

rm ~/.bashrc
ln -s ~/dotfiles/.bashrc ~/.bashrc

rm ~/.bash_profile
ln -s ~/dotfiles/.bash_profile ~/.bash_profile

source ~/.bash_profile 2> /dev/null

sudo apt install build-essential curl git unzip

curl -L https://go.dev/dl/go1.18.linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go.tar.gz
rm -rf go.tar.gz

go install golang.org/x/tools/cmd/goimports@latest
go install github.com/x-motemen/ghq@latest

curl https://sh.rustup.rs -sSf -o /tmp/rustup.rs 
sh /tmp/rustup.rs -y

curl -fsSL https://deno.land/install.sh | sh

# -----build vim-----
sudo apt remove vim
sudo apt autoremove vim

sudo apt install python-is-python3 libncurses5-dev python3-dev

ghq get https://github.com/vim/vim
cd ~/ghq/github.com/vim/vim/src
git checkout v8.2.4503

~/dotfiles/build-vim.sh && make && sudo make install && cd -

curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
# -------------------

sudo apt install tmux

# ----- git settings -----
git config --global user.name "Maru32768"
git config --global core.editor 'vim -c "set fenc=utf-8"'
git config --global color.diff auto
git config --global color.status auto
git config --global color.branch auto
git config --global color.ui true
git config --global push.default simple
git config --global core.ignorecase false
git config --global core.quotepath false
git config --global core.autocrlf false
git config --global merge.tool vimdiff
git config --global merge.conflictstyle diff3
git config --global mergetool.prompt false
# ------------------------

source ~/.bash_profile
