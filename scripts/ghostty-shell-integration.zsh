# Ghostty shell integration for dynamic window/tab titles
# Add this to your ~/.zshrc

# Function to set window and tab title based on current directory
ghostty_set_title() {
    # Get current working directory, with home folder abbreviated
    local cwd=${PWD/#$HOME/~}
    
    # Extract just the directory name for tab title
    local dir_name=${PWD##*/}
    
    # Set window title to full path, tab title to directory name
    # Using OSC 0 for window title and OSC 2 for tab title
    printf '\e]0;%s\a' "$cwd"        # Window title
    printf '\e]2;%s\a' "$dir_name"    # Tab title (if supported)
}

# Function that gets called after each command
ghostty_precmd() {
    ghostty_set_title
}

# Function that gets called before each command
ghostty_preexec() {
    # Optional: could show running command in title
    # local cmd="${1%% *}"  # Get first word of command
    # printf '\e]0;%s: %s\a' "${PWD##*/}" "$cmd"
}

# Set up the hooks if we're in Ghostty
if [[ "$TERM" == "xterm-ghostty" ]]; then
    # Add our functions to zsh's precmd and preexec arrays
    precmd_functions+=(ghostty_precmd)
    # preexec_functions+=(ghostty_preexec)  # Uncomment if you want command in title
    
    # Set initial title
    ghostty_set_title
fi