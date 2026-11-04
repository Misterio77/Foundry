cd "${PASSWORD_STORE_DIR:-$HOME/.password-store}"

if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
    class="$(hyprctl activewindow -j | jq -r '.class')"
elif [ "$XDG_CURRENT_DESKTOP" == "sway" ]; then
    focused="$(swaymsg -t get_tree | jq -r '.. | (.nodes? // empty)[] | select(.focused==true)')"
    class=$(jq -r '.window_properties.class' <<< "$focused")
fi

if [[ "$class" == "org.qutebrowser.qutebrowser" ]] || [[ "$class" == "qutebrowser" ]]; then
    # Synthetic keys can inherit held launcher modifiers and trigger WM bindings.
    qutebrowser ':yank url' ':mode-enter insert'
    sleep 0.2
    query=$(wl-paste | cut -d '/' -f3 | sed s/"www."//)
elif [[ "$class" == "discord" ]]; then
    query="discord.com"
elif [[ "$class" == "Steam" ]]; then
    query="steampowered.com"
fi

selected=$(find -L . -not -path '*\/.*' -path "*.gpg" -type f -printf '%P\n' | \
  sed 's/.gpg$//g' | \
  wofi -S dmenu -Q "$query") || exit 2

username=$(echo "$selected" | cut -d '/' -f2)
url=$(echo "$selected" | cut -d '/' -f1)

if [ -n "$1" ]; then
    field="$1"
    shift 1
else
    fields="Password
Username
OTP
URL
Fill"

    field=$(printf "$fields" | wofi -S dmenu) || field="password"
fi

secret=0

case "${field,,}" in
    "username")
        value="$username"
        ;;
    "url")
        value="$url"
        ;;
    "password")
        value="$(pass "$selected" | head -n 1)" && [ -n "$value" ] || \
            { notify-send "Error" "No password for $selected" -i error -t 6000; exit 3; }
        secret=1
        ;;
    "otp")
        value="$(pass otp "$selected")" || \
            { notify-send "Error" "No OTP for $selected" -i error -t 6000; exit 3; }
        secret=1
        ;;
    "fill")
        password="$(pass "$selected" | head -n 1)" && [ -n "$password" ] || \
            { notify-send "Error" "No password for $selected" -i error -t 6000; exit 3; }
        wtype "$username" -s 50 -k tab -s 50 "$password"
        if otp="$(pass otp "$selected")" && [ -n "$otp" ]; then
            field="OTP"
            value="$otp"
            secret=1
        fi
        ;;
    *)
        exit 4
esac


if [ -n "$value" ]; then
    if [ "$secret" = 1 ]; then
        mime="text/secret"
    else
        mime="text/plain"
    fi
    wl-copy -t "$mime" "$value"
fi
