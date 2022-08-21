function setCookie(name,value,days) {
    var expires = "";
    if (days) {
        var date = new Date();
        date.setTime(date.getTime() + (days*24*60*60*1000));
        expires = "; Expires=" + date.toUTCString();
    }
    var domain = "";
    var samesite = "";
    if (window.location.host == "fontes.dev.br" || window.location.host == "git.fontes.dev.br") {
        domain = "; Domain=fontes.dev.br";
        samesite = "; SameSite=None; Secure";
    }
    document.cookie = name + "=" + (value || "")  + expires + "; Path=/" + samesite + domain;
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
    document.cookie = name +'=; Path=/; Expires=Thu, 01 Jan 1970 00:00:01 GMT;';
}

let chosen_scheme_css = document.getElementById("scheme-css");

// Set a given scheme
function setTheme(scheme) {
    chosen_scheme_css.setAttribute(
        "href",
        "/assets/themes/" + scheme + ".css"
    );
    setCookie("fontes_theme", scheme);
}

// Get currently applied scheme
function getTheme() {
    let theme = getCookie("fontes_theme");

    if (theme != "null") {
        return theme;
    } else {
        return null;
    }
}

// Reset scheme to default
function resetTheme() {
    chosen_scheme_css.removeAttribute("href");
    eraseCookie("fontes_theme");
}

// Get stored scheme from cookies and reapply it
let stored = getTheme();
if (stored) {
    setTheme(stored);
}
