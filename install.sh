
---

## 🧾 `install.sh`

```bash
#!/bin/bash
set -e

TARGET="$HOME/bin/finder"

mkdir -p "$(dirname "$TARGET")"
cp finder.sh "$TARGET"
chmod +x "$TARGET"

# Copy default exclude list if missing
[ ! -f "$HOME/.finder_exclude" ] && cp .finder_exclude "$HOME/.finder_exclude"

echo "✅ Installed finder to $TARGET"
echo "👉 Add this to your shell config if not already in PATH:"
echo "   export PATH=\"\$HOME/bin:\$PATH\""
