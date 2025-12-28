#!/bin/bash
# Juno Uninstaller

JUNO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect shell config
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.profile"
fi

echo "Juno Uninstaller"
echo "================"
echo ""

# Remove from shell config
if grep -q "JUNO_HOME" "$SHELL_RC" 2>/dev/null; then
    # Create backup
    cp "$SHELL_RC" "$SHELL_RC.backup"
    
    # Remove Juno lines
    grep -v "JUNO_HOME" "$SHELL_RC.backup" | grep -v "# Juno Language" > "$SHELL_RC"
    
    echo "Removed from $SHELL_RC"
    echo "Backup: $SHELL_RC.backup"
else
    echo "Juno not found in $SHELL_RC"
fi

echo ""
echo "To complete uninstall, delete the juno folder:"
echo "  rm -rf $JUNO_DIR"
echo ""
echo "Then restart terminal or run:"
echo "  source $SHELL_RC"
