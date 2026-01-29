# Tmux Clipboard Debugging Steps

## After restarting tmux, run these commands:

### 1. Check TERM outside tmux
```bash
echo $TERM
# Should match the pattern in terminal-overrides (expecting "xterm-ghostty")
```

### 2. Check clipboard settings inside tmux
```bash
tmux info | grep -i clip
tmux info | grep Ms
```

### 3. Test OSC52 directly
```bash
printf '\033]52;c;%s\007' "$(echo -n 'test' | base64)"
# Then try Cmd+V somewhere - should paste "test"
```

## If still not working, try updating tmux.conf:

Change this line:
```
set-option -ga terminal-overrides ",xterm-ghostty:Ms=\\E]52;c;%p2%s\\7"
```

To this (adds %p1%.0s to discard selection type):
```
set-option -ga terminal-overrides ",xterm-ghostty:Ms=\\E]52;c%p1%.0s;%p2%s\\7"
```

Then kill tmux server and restart:
```bash
tmux kill-server
```
