#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e 

echo "🚀 Bootstrapping Advanced AI Developer Environment..."

# ---------------------------------------------------------
# 1. Prerequisites Check
# ---------------------------------------------------------
echo "🔍 Checking prerequisites..."
for req in node npm curl; do
    if ! command -v $req &> /dev/null; then
        echo "❌ Error: $req is not installed. Please install it first."
        exit 1
    fi
done

# ---------------------------------------------------------
# 2. Terminal-Based AI Agents (Claude Code & OpenCode)
# ---------------------------------------------------------
echo "📦 Installing Claude Code (Anthropic)..."
npm install -g @anthropic-ai/claude-code

echo "📦 Installing OpenCode (Open-Source Agent)..."
npm install -g opencode-ai

# ---------------------------------------------------------
# 3. Factory Droid (Enterprise/Agentic CLI)
# ---------------------------------------------------------
echo "📦 Installing Factory Droid..."
curl -fsSL https://app.factory.ai/cli | sh

# ---------------------------------------------------------
# 4. Configuration Bootstrapping
# ---------------------------------------------------------
echo "⚙️ Bootstrapping configuration files..."

# OpenCode Config
mkdir -p ~/.config/opencode
cat << 'EOF' > ~/.config/opencode/opencode.json
{
  "provider": "openai",
  "model": "gpt-4o",
  "mcp": {}
}
EOF

# Global ENV variables profile (appends if not exists)
PROFILE_FILE="$HOME/.bashrc"
[[ "$OSTYPE" == "darwin"* ]] && PROFILE_FILE="$HOME/.zshrc"

if ! grep -q "ANTHROPIC_API_KEY" "$PROFILE_FILE"; then
cat << 'EOF' >> "$PROFILE_FILE"

# --- AI Coding Agent API Keys ---
# export ANTHROPIC_API_KEY="your-claude-key-here"
# export OPENAI_API_KEY="your-openai-key-here"
# export FACTORY_API_KEY="your-droid-key-here"
# export GEMINI_API_KEY="your-gemini-key-here"
EOF
    echo "✅ Appended API key placeholders to $PROFILE_FILE"
fi

# ---------------------------------------------------------
# 5. IDE Extensions (VS Code)
# ---------------------------------------------------------
echo "🧩 Installing VS Code Extensions..."
if command -v code &> /dev/null; then
    # GitHub Copilot & Chat
    code --install-extension GitHub.copilot --force
    code --install-extension GitHub.copilot-chat --force
    
    # Gemini (via Google Cloud Code)
    code --install-extension GoogleCloudTools.cloudcode --force
    
    # Continue.dev (Handles OpenAI/Codex successors, local models, etc.)
    code --install-extension Continue.continue --force
    
    echo "✅ VS Code extensions installed."
else
    echo "⚠️ VS Code CLI ('code') not found. Skipping extension installations."
    echo "   If you use Cursor or Windsurf, extensions may need manual installation."
fi

echo "🎉 Installation complete! Please open $PROFILE_FILE to set your API keys."
