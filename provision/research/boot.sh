#!/bin/bash
# research の wsl.conf の [boot] command。root で実行される。
# agent と同じく共有のマウントを外し、research の通信の制限を読み込む。
# 読み込めなかったときは、research-claude の起動前の検査で止まる。
/usr/local/sbin/agent-isolate-mounts
/usr/local/sbin/research-firewall
