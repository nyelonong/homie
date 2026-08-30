#!/bin/bash

# Workspace pill click: jump to the clicked workspace (arg: workspace number).
"${OMNIWMCTL_BIN:-/opt/homebrew/bin/omniwmctl}" command switch-workspace "$1"
