{
  config,
  lib,
  ...
}: {
  services.hypridle = {
    enable = true;
    settings = let
      dpms = action: "hyprctl eval 'require(\"dpms_guard\").${action}()'";
      isLocked = "pgrep -x swaylock";
    in {
      general = {
        lock_cmd = "if ! ${isLocked}; then ${lib.getExe' config.programs.swaylock.package "swaylock"} -i ${config.wallpaper} --grace 5 --grace-no-mouse; fi";
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

        {
          timeout = 900;
          on-timeout = "systemd-analyze condition ConditionACPower=false && systemctl suspend";
        }
      ];
    };
  };
}
