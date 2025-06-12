#!/bin/bash
set -e
set -o pipefail

CACHE_DIR="$HOME/.cache/finder"
LAST_SEARCH="$CACHE_DIR/last_search.txt"
EXCLUDE_FILE="$HOME/.finder_exclude"
mkdir -p "$CACHE_DIR"

trap cleanup SIGINT SIGTERM

cleanup() {
  echo -e "\n❌ Operation cancelled. Cleaning up..."
  kill 0 2>/dev/null || true
  exit 1
}

spinner() {
  local pid=$1
  local delay=0.3
  local frames=("." ".." "...")
  while kill -0 "$pid" 2>/dev/null; do
    for frame in "${frames[@]}"; do
      printf "\r🔄 Working%s" "$frame"
      sleep "$delay"
    done
  done
  printf "\r✅ Done!            \n"
}

show_help() {
  cat <<EOF
Usage: finder [options]

Options:
  -x               Exclude common heavy dirs (e.g., .git, node_modules)
  --no-exclude     Disable automatic exclusion for large directories
  --no-save        Don't save search results
  --last           Show results of the last search
  -h, --help       Show this help message

Config:
  ~/.finder_exclude - Add custom folder names to exclude (one per line)
EOF
  exit 0
}

# --- ARGUMENT FLAGS ---
exclude_flag=false
no_exclude_override=false
save_results=true
show_last=false

for arg in "$@"; do
  case "$arg" in
    -x) exclude_flag=true ;;
    --no-exclude) no_exclude_override=true ;;
    --no-save) save_results=false ;;
    --last) show_last=true ;;
    -h|--help) show_help ;;
    *) echo "❌ Unknown argument: $arg"; show_help ;;
  esac
done

# --- Show last search if requested ---
if [ "$show_last" = true ]; then
  if [ -f "$LAST_SEARCH" ]; then
    echo "📂 Last Search Results:"
    cat "$LAST_SEARCH"
  else
    echo "ℹ️ No previous search found."
  fi
  exit 0
fi

# --- Exclusion file setup ---
if [ ! -f "$EXCLUDE_FILE" ]; then
  cat > "$EXCLUDE_FILE" <<EOF
.git
node_modules
vendor
.cache
dist
build
EOF
  echo "📝 Created default exclude list at $EXCLUDE_FILE"
  echo "  (edit it to customize your exclusions)"
fi

# --- Directory Heaviness Check ---
dir_count=$(find . -type d 2>/dev/null | wc -l)
if [ "$dir_count" -gt 1000 ] && [ "$no_exclude_override" = false ]; then
  echo "⚠️ Large directory detected ($dir_count folders)"
  echo "💡 Enabling directory exclusion (-x) automatically."
  exclude_flag=true
fi

# --- UI ---
echo "--------------------------------------"
echo "🔎 FINDER CLI with caching, exclusions, history"
echo "--------------------------------------"

read -rp "Enter search pattern (use wildcards like '*pass*'): " pattern
[[ -z "$pattern" ]] && echo "❌ No pattern entered. Exiting." && exit 1

read -rp "Search for (f)iles or (d)irectories? [f/d]: " type_choice
case "$type_choice" in
  [fF]) file_type="f"; type_label="files" ;;
  [dD]) file_type="d"; type_label="dirs" ;;
  *) echo "❌ Invalid type. Exiting."; exit 1 ;;
esac

read -rp "Search in (c)urrent dir or (r)ecursively? [c/r]: " scope_choice
case "$scope_choice" in
  [cC]) find_options="-maxdepth 1"; scope_label="shallow" ;;
  [rR]) find_options=""; scope_label="deep" ;;
  *) echo "❌ Invalid scope. Exiting."; exit 1 ;;
esac

suffix=""
[ "$exclude_flag" = true ] && suffix="_x"
cache_file="$CACHE_DIR/${type_label}_${scope_label}${suffix}.cache"

# --- Cache Handling ---
if [ -f "$cache_file" ]; then
  echo "🗂️  Cache file found: $cache_file"
  read -rp "Use existing cache? (y)es / (r)ebuild / (d)elete: " cache_choice
  case "$cache_choice" in
    [rR]) echo "🔄 Rebuilding..."; rm -f "$cache_file" ;;
    [dD]) echo "🗑️  Deleted."; rm -f "$cache_file"; exit 0 ;;
    [yY]) echo "✅ Using cache..." ;;
    *) echo "❌ Invalid choice. Exiting."; exit 1 ;;
  esac
fi

# --- Build Cache ---
if [ ! -f "$cache_file" ]; then
  echo "⚙️  Building cache..."

  if [ "$exclude_flag" = true ]; then
    exclude_terms=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && exclude_terms+=("$line")
    done < "$EXCLUDE_FILE"

    # Build a clean find command with exclusions
    find_args=(. $find_options)
    for ex in "${exclude_terms[@]}"; do
      find_args+=(-path "*/$ex" -prune -o)
    done
    find_args+=(-type "$file_type" -print)

    # Run the find command safely
    find "${find_args[@]}" > "$cache_file" &
  else
    # Simple non-excluded find
    find . $find_options -type "$file_type" -print > "$cache_file" &
  fi

  spinner $!
fi

# --- Run Search ---
echo "--------------------------------------"
echo "🔍 Searching..."
matches_found=false
pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')

run_search() {
  while IFS= read -r line; do
    name_part=$(basename "$line")
    name_lower=$(echo "$name_part" | tr '[:upper:]' '[:lower:]')

    if [[ "$name_lower" == $pattern_lower ]]; then
      echo "$line"
      matches_found=true
      echo "$line" >> "$LAST_SEARCH"
    fi
  done < "$cache_file"
}

# Clear previous last search
[ "$save_results" = true ] && > "$LAST_SEARCH"

run_search &
search_pid=$!
spinner "$search_pid"
wait "$search_pid"

if [ "$matches_found" = false ]; then
  echo "🔍 No matches found."
fi

echo "--------------------------------------"
echo "✅ Search complete."
