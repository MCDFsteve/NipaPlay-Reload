#!/bin/zsh
# 调用：lockf -k $HOME/.nipa-next/mac-lab.lock zsh docs/next/evidence/pc-sources/experiment.sh servers
set -eu
cd /Users/sakiko/Desktop/nipaplay-next-wt/pc-sources
python3 docs/next/evidence/pc-sources/experiment.py "${1:-servers}"
