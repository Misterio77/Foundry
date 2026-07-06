{config, ...}: let
  c = config.colorscheme.colors;
  tmux = "${config.programs.tmux.package}/bin/tmux";
in {
  programs.tmux = {
    enable = true;
    mouse = true;
    historyLimit = 100000;
    keyMode = "vi";
    prefix = "M-Space";
    escapeTime = 0;
    terminal = "tmux-256color";
    baseIndex = 1;

    extraConfig = ''
      # Better modified-key handling for modern terminal TUIs/editors
      set -g extended-keys on
      set -g extended-keys-format csi-u

      # Keep window numbers compact after closing windows
      set -g renumber-windows on

      # Make terminal/window titles identify the tmux session
      set -g set-titles on
      set -g set-titles-string '#S:#W'

      # Theme tmux UI from the active colorscheme
      set -g status-style 'bg=${c.surface},fg=${c.on_surface}'
      set -g status-left-style 'fg=${c.primary}'
      set -g status-right-style 'fg=${c.on_surface_variant}'
      set -g window-status-style 'fg=${c.on_surface_variant}'
      set -g window-status-current-style 'bg=${c.primary_container},fg=${c.on_primary_container}'
      set -g pane-border-style 'fg=${c.outline_variant}'
      set -g pane-active-border-style 'fg=${c.primary}'
      set -g message-style 'bg=${c.primary_container},fg=${c.on_primary_container}'
      set -g mode-style 'bg=${c.secondary_container},fg=${c.on_secondary_container}'

      # More ergonomic splits
      bind | split-window -h
      bind - split-window -v

      # Prefix ? shows the active prefix key bindings
      bind ? display-popup -E "${config.programs.tmux.package}/bin/tmux list-keys -T prefix | less"

      # Normal mode: Alacritty-ish scrollback
      bind -n S-PPage copy-mode -u
      bind -n S-NPage copy-mode \; send -X page-down \; if -F '#{==:#{scroll_position},0}' 'send -X cancel'
      bind -n S-Home  copy-mode \; send -X history-top
      bind -n S-End   copy-mode \; send -X history-bottom \; send -X cancel

      # Enter copy mode
      # Note: terminals often can't distinguish Ctrl+Shift+Space from Ctrl+Space
      bind -n C-Space copy-mode

      # Copy mode: Alacritty-ish movement
      bind -T copy-mode-vi S-PPage send -X page-up
      bind -T copy-mode-vi S-NPage send -X page-down \; if -F '#{==:#{scroll_position},0}' 'send -X cancel'
      bind -T copy-mode-vi S-Home  send -X history-top
      bind -T copy-mode-vi S-End   send -X cancel

      # Copy mode: vim-ish exit
      bind -T copy-mode-vi i send -X cancel

      # Keep Ctrl-d from auto-exiting at bottom
      bind -T copy-mode-vi C-d send -X halfpage-down
    '';
  };

  xdg.configFile."tmux/tmux.conf".onChange = ''
    ${tmux} list-sessions >/dev/null 2>&1 && ${tmux} source-file "$HOME/.config/tmux/tmux.conf" || true
  '';
}
