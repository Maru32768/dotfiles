#!/bin/bash

rm ~/.vimrc
ln -s ~/dotfiles/vim/.vimrc ~/.vimrc

rm ~/.bashrc
ln -s ~/dotfiles/.bashrc ~/.bashrc

rm ~/.bash_profile
ln -s ~/dotfiles/.bash_profile ~/.bash_profile

sudo apt install git
sudo apt install build-essential

curl -L https://go.dev/dl/go1.17.8.linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go.tar.gz
rm -rf go.tar.gz

go install golang.org/x/tools/cmd/goimports@latest
go install github.com/x-motemen/ghq@latest

curl https://sh.rustup.rs -sSf -o /tmp/rustup.rs | sh /tmp/rustup.rs -y

curl -fsSL https://deno.land/install.sh | sh

sudo apt install tmux

sudo apt remove vim
sudo apt autoremove vim

sudo apt install python-is-python3
sudo apt install python3-dev

ghq get https://github.com/vim/vim
cd ~/ghq/github.com/vim/vim/src
git checkout v8.2.4503
~/dotfiles/build-vim.sh && make && sudo make install && cd -

source ~/.bashrc
source ~/.bash_profile
