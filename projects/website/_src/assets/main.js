---
layout: null
---

var schemes = {{ site.data.colorscheme.schemes | jsonify }};
var schemeNames = Object.keys(schemes).filter(function (name) {
    return name !== "print";
});
var chosenSchemeStyle = null;

function setCookie(name, value, days) {
    var expires = "";
    if (days) {
        var date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; Expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + encodeURIComponent(value) + expires + "; Path=/; SameSite=Lax";
}

function getCookie(name) {
    var prefix = name + "=";
    var cookies = document.cookie.split(";");
    for (var i = 0; i < cookies.length; i++) {
        var cookie = cookies[i].trim();
        if (cookie.indexOf(prefix) === 0) {
            return decodeURIComponent(cookie.substring(prefix.length));
        }
    }
    return null;
}

function eraseCookie(name) {
    document.cookie = name + "=; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Path=/; SameSite=Lax";
}

function setTheme(scheme, persist) {
    var colors = schemes[scheme];
    if (!colors || scheme === "print") return;

    if (!chosenSchemeStyle) {
        chosenSchemeStyle = document.createElement("style");
        chosenSchemeStyle.id = "theme-css";
        document.head.appendChild(chosenSchemeStyle);
    }

    var css = ":root {\n";
    for (var key in colors) {
        if (Object.prototype.hasOwnProperty.call(colors, key)) {
            css += "  --" + key + ": " + colors[key] + ";\n";
        }
    }
    css += "}";
    chosenSchemeStyle.textContent = css;

    var picker = document.getElementById("scheme-select");
    if (picker) picker.value = scheme;
    if (persist !== false) setCookie("fontes_theme", scheme, 365);
}

function getTheme() {
    var theme = getCookie("fontes_theme");
    return schemeNames.indexOf(theme) >= 0 ? theme : null;
}

function resetTheme() {
    if (chosenSchemeStyle) {
        chosenSchemeStyle.remove();
        chosenSchemeStyle = null;
    }
    eraseCookie("fontes_theme");

    var picker = document.getElementById("scheme-select");
    if (picker) picker.value = "{{ site.default_scheme }}";
}

var storedTheme = getTheme();
if (storedTheme) setTheme(storedTheme, false);

document.addEventListener("DOMContentLoaded", function () {
    var picker = document.getElementById("scheme-select");
    if (!picker) return;

    picker.parentElement.hidden = false;
    picker.value = storedTheme || "{{ site.default_scheme }}";
    picker.addEventListener("change", function () {
        setTheme(picker.value);
    });
});
