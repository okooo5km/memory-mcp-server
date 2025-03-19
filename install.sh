#!/bin/bash

# Memory MCP Server Installation Script
# https://github.com/5km/memory-mcp-server

set -e

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing Memory MCP Server...${NC}"

# Create ~/.local/bin directory (if it doesn't exist)
if [ ! -d "$HOME/.local/bin" ]; then
  echo -e "${YELLOW}Creating ~/.local/bin directory...${NC}"
  mkdir -p "$HOME/.local/bin"
fi

# Add to PATH based on the current shell (if not already added)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo -e "${YELLOW}Adding ~/.local/bin to your PATH...${NC}"
  
  # We need to detect the user's actual login shell, not the shell running this script
  USER_SHELL=$(basename "$SHELL")
  
  # Determine shell configuration file based on user's login shell, not the current shell
  if [ -f "$HOME/.zshrc" ] && [[ "$USER_SHELL" == "zsh" ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
    echo -e "${BLUE}Detected ZSH as your login shell${NC}"
  elif [ -f "$HOME/.bashrc" ] && [[ "$USER_SHELL" == "bash" ]]; then
    SHELL_CONFIG="$HOME/.bashrc"
    echo -e "${BLUE}Detected Bash as your login shell${NC}"
  # Check for common shell configuration files as fallbacks
  elif [ -f "$HOME/.zshrc" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
    echo -e "${BLUE}Found .zshrc configuration file${NC}"
  elif [ -f "$HOME/.bashrc" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
    echo -e "${BLUE}Found .bashrc configuration file${NC}"
  else
    SHELL_CONFIG="$HOME/.profile"
    echo -e "${YELLOW}Using ~/.profile as fallback${NC}"
  fi
  
  if [ -f "$SHELL_CONFIG" ] || [ "$SHELL_CONFIG" = "$HOME/.profile" ]; then
    if [ ! -f "$SHELL_CONFIG" ]; then
      touch "$SHELL_CONFIG"
    fi
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_CONFIG"
    echo -e "${GREEN}Added PATH to $SHELL_CONFIG${NC}"
    echo -e "${YELLOW}Note: You'll need to restart your terminal or run 'source $SHELL_CONFIG' for this change to take effect${NC}"
  else
    echo -e "${RED}Warning: Could not find shell configuration file. Please add ~/.local/bin to your PATH manually.${NC}"
  fi
fi

# Download and install the latest version
echo -e "${BLUE}Downloading the latest version...${NC}"
if ! curl -L "https://github.com/5km/memory-mcp-server/releases/latest/download/memory-mcp-server.tar.gz" | tar xz -C "$HOME/.local/bin"; then
  echo -e "${RED}Error: Failed to download or extract the binary.${NC}"
  exit 1
fi

chmod +x "$HOME/.local/bin/memory-mcp-server"

# Verify installation
if [ -x "$HOME/.local/bin/memory-mcp-server" ]; then
  echo -e "${GREEN}✅ Installation completed successfully!${NC}"
  
  # Check if executable is in PATH
  if command -v memory-mcp-server >/dev/null 2>&1; then
    echo -e "${GREEN}memory-mcp-server is in your PATH and ready to use.${NC}"
    echo -e "${BLUE}Version information:${NC}"
    memory-mcp-server --version
  else
    echo -e "${YELLOW}Note: memory-mcp-server is installed but may not be in your current PATH.${NC}"
    echo -e "${YELLOW}Run the following command to use it immediately:${NC}"
    echo -e "${BLUE}$HOME/.local/bin/memory-mcp-server --version${NC}"
    echo -e "${YELLOW}Or restart your terminal session for PATH changes to take effect.${NC}"
  fi
  
  echo -e "\n${BLUE}For Configuration Instructions:${NC}"
  echo -e "You can set the knowledge graph path using the environment variable:"
  echo -e "${GREEN}export MEMORY_FILE_PATH=\"/path/to/your/memory.json\"${NC}"
  echo -e "By default, the memory is stored in memory.json in the current directory."
else
  echo -e "${RED}Error: Installation failed. The binary is not executable.${NC}"
  exit 1
fi 