---
layout: null
---

function setCookie(name,value,days) {
    var expires = "";
    if (days) {
        if (days < 0) {
            expires = "; Expires=Thu, 01 Jan 1970 00:00:01 GMT"
        } else {
            var date = new Date();
            date.setTime(date.getTime() + (days*24*60*60*1000));
            expires = "; Expires=" + date.toUTCString();
        }
    }
    document.cookie = name + "=" + (value || "")  + expires + "; Path=/";
}
function getCookie(name) {
    var nameEQ = name + "=";
    var ca = document.cookie.split(';');
    for(var i=0;i < ca.length;i++) {
        var c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1,c.length);
        if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
    }
    return null;
}
function eraseCookie(name) {
    setCookie(name, "", -1);
}

var schemes = {{ site.data.colorscheme.schemes | jsonify }};
var chosen_scheme_style = null;

// Set a given scheme
function setTheme(scheme) {
    var colors = schemes[scheme];
    if (!colors) return;

    if (!chosen_scheme_style) {
        chosen_scheme_style = document.createElement("style");
        chosen_scheme_style.id = "theme-css";
        document.head.appendChild(chosen_scheme_style);
    }
    var css = ":root {\n";
    for (var key in colors) {
        if (colors.hasOwnProperty(key)) {
            css += "  --" + key + ": " + colors[key] + ";\n";
        }
    }
    css += "}";
    chosen_scheme_style.textContent = css;
    setCookie("fontes_theme", scheme);
}

// Get currently applied scheme
function getTheme() {
    var theme = getCookie("fontes_theme");

    if (theme != "null") {
        return theme;
    } else {
        return null;
    }
}

// Reset scheme to default
function resetTheme() {
    if (chosen_scheme_style) {
        chosen_scheme_style.remove();
        chosen_scheme_style = null;
    }
    eraseCookie("fontes_theme");
}

// Get stored scheme from cookies and reapply it
var stored = getTheme();
if (stored) {
    setTheme(stored);
}
