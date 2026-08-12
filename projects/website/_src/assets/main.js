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
            css += "  --palette-" + key + ": " + colors[key] + ";\n";
        }
    }
    css += "}";
    chosenSchemeStyle.textContent = css;

    updateThemeControls(scheme);
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

    updateThemeControls("{{ site.default_scheme }}");
}

function updateThemeControls(scheme) {
    var buttons = document.querySelectorAll("[data-scheme]");
    for (var i = 0; i < buttons.length; i++) {
        var active = buttons[i].getAttribute("data-scheme") === scheme;
        buttons[i].setAttribute("aria-pressed", active ? "true" : "false");
    }

}

var storedTheme = getTheme();
if (storedTheme) setTheme(storedTheme, false);

document.addEventListener("DOMContentLoaded", function () {
    var constellation = document.querySelector(".theme-constellation");
    if (!constellation) return;

    constellation.hidden = false;
    updateThemeControls(storedTheme || "{{ site.default_scheme }}");

    var buttons = constellation.querySelectorAll("[data-scheme]");
    for (var i = 0; i < buttons.length; i++) {
        buttons[i].addEventListener("click", function () {
            setTheme(this.getAttribute("data-scheme"));
        });
    }
});
