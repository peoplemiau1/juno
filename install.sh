#!/bin/bash
# Juno Language Installer
# Adds juno to your PATH

JUNO_DIR="$(cd "$(dirname "$0")" && pwd)"
SHELL_RC=""

# Detect shell
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.profile"
fi

echo "🚀 Juno Language Installer"
echo "=========================="
echo ""
echo "Juno directory: $JUNO_DIR"
echo "Shell config:   $SHELL_RC"
echo ""

# Check if already installed
if grep -q "JUNO_HOME" "$SHELL_RC" 2>/dev/null; then
    echo "⚠️  Juno is already in your PATH"
    echo "   To reinstall, first remove the JUNO lines from $SHELL_RC"
    exit 0
fi

# Add to PATH
echo "" >> "$SHELL_RC"
echo "# Juno Language" >> "$SHELL_RC"
echo "export JUNO_HOME=\"$JUNO_DIR\"" >> "$SHELL_RC"
echo 'export PATH="$JUNO_HOME:$PATH"' >> "$SHELL_RC"

echo "✅ Added to $SHELL_RC"
echo ""
echo "To start using juno, run:"
echo "  source $SHELL_RC"
echo ""
echo "Or open a new terminal."
echo ""
echo "Then try:"
echo "  juno help"
echo "  juno new hello"
echo "  juno run hello.juno"
echo ""
echo "🔥 For anti-reverse-engineering:"
echo "  juno build secret.juno --hell"
