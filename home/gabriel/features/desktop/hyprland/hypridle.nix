{
  config,
  lib,
  ...
}: {
  services.hypridle = {
    enable = true;
    settings = let
      dpms = action: "hyprctl dispatch 'hl.dsp.dpms({ action = \"${action}\" })'";
      isLocked = "pgrep hyprlock";
      isDischarging = "grep Discharging /sys/class/power_supply/BAT{0,1}/status -q";
    in {
      general = {
        lock_cmd = "if ! ${isLocked}; then ${lib.getExe config.programs.hyprlock.package} --grace 5; fi";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = dpms "enable";
        inhibit_sleep = 3; # Wait for lock before suspend
      };
      listener = [
        {
          timeout = 10;
          on-timeout = "brightnessctl --save";
          on-resume = "brightnessctl --restore";
        }
        {
          timeout = 30;
          on-timeout = "brightnessctl --device *:kbd_backlight --save set 0";
          on-resume = "brightnessctl --device *:kbd_backlight --restore";
        }
        {
          timeout = 50;
          on-timeout = "brightnessctl set 25%- -n 1";
        }
        {
          timeout = 110;
          on-timeout = "brightnessctl set 50%- -n 1";
        }
        {
          timeout = 120;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 140;
          on-timeout = dpms "disable";
          on-resume = dpms "enable";
        }

        # If already locked
        {
          timeout = 15;
          on-timeout = "if ${isLocked}; then brightnessctl set 75%- -n 1; fi";
        }
        {
          timeout = 20;
          on-timeout = "if ${isLocked}; then ${dpms "disable"}; fi";
          on-resume = dpms "enable";
        }

        # If discharging
        {
          timeout = 900;
          on-timeout = "if ${isDischarging}; then systemctl suspend; fi";
        }
      ];
    };
  };
}
