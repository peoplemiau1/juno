#!/bin/bash
# Juno Language Installer

JUNO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect shell config
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.profile"
fi

echo "Juno Installer"
echo "=============="
echo ""
echo "Directory: $JUNO_DIR"
echo "Config:    $SHELL_RC"
echo ""

# Check if already installed
if grep -q "JUNO_HOME" "$SHELL_RC" 2>/dev/null; then
    echo "Juno is already installed."
    echo ""
    echo "To update:"
    echo "  cd $JUNO_DIR && git pull"
    echo ""
    echo "To reinstall:"
    echo "  1. Remove these lines from $SHELL_RC:"
    echo "     # Juno Language"
    echo "     export JUNO_HOME=..."
    echo "     export PATH=..."
    echo "  2. Run ./install.sh again"
    echo ""
    echo "To uninstall completely:"
    echo "  1. Remove lines from $SHELL_RC (see above)"
    echo "  2. rm -rf $JUNO_DIR"
    exit 0
fi

# Add to PATH
echo "" >> "$SHELL_RC"
echo "# Juno Language" >> "$SHELL_RC"
echo "export JUNO_HOME=\"$JUNO_DIR\"" >> "$SHELL_RC"
echo 'export PATH="$JUNO_HOME:$PATH"' >> "$SHELL_RC"

echo "Installed successfully."
echo ""
echo "Run this to activate:"
echo "  source $SHELL_RC"
echo ""
echo "Then try:"
echo "  juno help"
echo "  juno new hello"
echo "  juno run hello.juno"
