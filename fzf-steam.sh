#!/usr/bin/env bash
# Steam Game Launcher
# Generates .desktop entries for all installed Steam games with box art for
# the icons to be used with fzf for game selection

# Use more robust variable quoting and command substitution
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Store configuration in variables for easy customization
STEAM_ROOT="$HOME/.local/share/Steam/steamapps"
APP_PATH="$HOME/.local/share/applications/steam"
CACHE_DIR="$HOME/.cache/steam-launcher"
LOG_FILE="$CACHE_DIR/launcher.log"

# Create necessary directories
mkdir -p "$APP_PATH" "$CACHE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Fetch all Steam library folders including additional libraries
steam_libraries() {
    # Start with the main Steam library
    echo "$STEAM_ROOT"
    
    # Additional library folders are recorded in libraryfolders.vdf
    local libraryfolders="$STEAM_ROOT/libraryfolders.vdf"
    
    if [ -e "$libraryfolders" ]; then
        # Extract all library paths using awk
        awk -F\" '/^[[:space:]]*"[[:digit:]]+"/ {print $4}' "$libraryfolders"
    fi
}

# Generate the contents of an environment file for a Steam game
create_game_env() {
    local appid="$1"
    local title="$2"
    local boxart="$3"
    
    cat <<EOF
GAME_ID="$appid"
GAME_NAME="$title"
GAME_ICON="$boxart"
EOF
}

# Filter function to exclude non-game entries
is_game() {
    local title="$1"
    
    # Filter out non-game entries (DLCs, soundtracks, tools, etc.)
    if echo "$title" | grep -qiE '(soundtrack|proton|runtime|server|dedicated|sdk|tool|demo|beta)'; then
        return 1
    fi
    
    return 0
}

# Main function to scan libraries and generate game entries
generate_game_entries() {
    log "Starting game entry generation"
    
    # Clear existing entries to avoid duplicates if desired
    # rm -f "$APP_PATH"/*.env
    
    local game_count=0
    
    for library in $(steam_libraries); do
        log "Scanning library: $library"
        
        # All installed Steam games correspond with an appmanifest_<appid>.acf file
        for manifest in "$library"/appmanifest_*.acf; do
            # Skip if no manifests found
            [ -e "$manifest" ] || continue
            
            # Extract app ID and title
            appid=$(basename "$manifest" | tr -dc "0-9")
            title=$(awk -F\" '/"name"/ {print $4}' "$manifest" | tr -d "™®©")
            
            # Skip non-games
            if ! is_game "$title"; then
                continue
            fi
            
            # Define entry and boxart paths
            entry="$APP_PATH/${title// /_}.env"
            boxart="$STEAM_ROOT/../appcache/librarycache/${appid}_library_600x900.jpg"
            
            # Check if boxart exists
            if [ ! -f "$boxart" ]; then
                log "Warning: No boxart found for $title ($appid)"
                # Use a fallback icon if desired
                # boxart="/usr/share/icons/hicolor/256x256/apps/steam.png"
            fi
            
            # Generate entry file
            create_game_env "$appid" "$title" "$boxart" > "$entry"
            
            game_count=$((game_count + 1))
            log "Generated entry for: $title ($appid)"
        done
    done
    
    log "Completed generation of $game_count game entries"
}

# Launch the selected game
launch_game() {
    # Change to the directory with env files
    cd "$APP_PATH" || { 
        echo "Error: Could not access $APP_PATH" >&2
        exit 1
    }
    
    # Get a list of all game env files
    local game_list=(*.env)
    
    # Check if any games were found
    if [ ${#game_list[@]} -eq 0 ]; then
        echo "No games found. Run the script with --generate first." >&2
        exit 1
    fi
    
    # Use fzf to select a game, with preview of game info
    selected=$(ls -1 | sed -e 's/\.env$//' | 
              fzf --border --preview="cat {}.env | sed 's/^/  /'" --preview-window=up:3:wrap)
    
    # Exit if no selection was made
    [ -z "$selected" ] && exit 0
    
    # Load the selected game's environment variables
    if [ -f "${selected}.env" ]; then
        # shellcheck disable=SC1090
        source "${selected}.env"
        
        echo "Launching: $GAME_NAME"
        log "Launching game: $GAME_NAME ($GAME_ID)"
        
        # Launch the game directly without lnch
        nohup steam-runtime steam://rungameid/"$GAME_ID" > /dev/null 2>&1 &
        
        # Return to terminal immediately
        disown
    else
        echo "Error: Could not find game data for $selected" >&2
        exit 1
    fi
}

# Show help message
show_help() {
    cat << EOF
Steam Game Launcher

Usage: $(basename "$0") [OPTION]

Options:
  -g, --generate    Generate game entries
  -l, --launch      Launch game selector
  -h, --help        Show this help message

Without options, both generate and launch actions will be performed.
EOF
}

# Main script logic with command-line argument handling
case "$1" in
    -g|--generate)
        generate_game_entries
        ;;
    -l|--launch)
        launch_game
        ;;
    -h|--help)
        show_help
        ;;
    *)
        # Default behavior: generate and launch
        generate_game_entries
        launch_game
        ;;
esac

exit 0
