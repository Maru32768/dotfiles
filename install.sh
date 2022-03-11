#!/bin/bash

ln -s ~/dotfiles/vim/.vimrc ~/.vimrc
ln -s ~/dotfiles/.bashrc ~/.bashrc
ln -s ~/dotfiles/.bash_profile ~/.bash_profile

curl -L https://go.dev/dl/go1.17.8.linux-amd64.tar.gz -o go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go.tar.gz
rm -rf go.tar.gz

echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bash_profile
echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.bash_profile
echo "export PATH=\$PATH:\$HOME/go/bin" >> ~/.bash_profile

curl https://sh.rustup.rs -sSf -o /tmp/rustup.rs | sh /tmp/rustup.rs -y
echo "source \$HOME/.cargo/env"

echo "export MYVIMRC=\$HOME/.vimrc" >> ~/.bash_profile

curl -fsSL https://deno.land/install.sh | sh
echo "export DENO_INSTALL=\$HOME/.deno" >> ~/.bash_profile
echo "export PATH=\$PATH:\$DENO_INSTALL/bin" >> ~/.bash_profile
