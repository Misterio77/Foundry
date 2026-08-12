---
layout: null
---

var schemes = {{ site.data.colorscheme | jsonify }};
var schemeNames = Object.keys(schemes);
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

function colorDeclarations(colors) {
    var css = "";
    for (var key in colors) {
        if (Object.prototype.hasOwnProperty.call(colors, key)) {
            css += "    --" + key + ": " + colors[key] + ";\n";
        }
    }
    return css;
}

function setTheme(scheme, persist) {
    var colors = schemes[scheme] && schemes[scheme].colors;
    if (!colors) return;

    if (!chosenSchemeStyle) {
        chosenSchemeStyle = document.createElement("style");
        chosenSchemeStyle.id = "theme-css";
        document.head.appendChild(chosenSchemeStyle);
    }

    chosenSchemeStyle.textContent =
        ":root {\n" + colorDeclarations(colors.dark) + "}\n" +
        "@media (prefers-color-scheme: light) {\n  :root {\n" + colorDeclarations(colors.light) + "  }\n}\n" +
        "@media print {\n  :root {\n" + colorDeclarations(colors.light) + "  }\n}";

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
    var headings = document.querySelectorAll("main :is(h2, h3, h4, h5, h6)[id]");
    for (var i = 0; i < headings.length; i++) {
        var permalink = document.createElement("a");
        permalink.className = "heading-permalink";
        permalink.href = "#" + encodeURIComponent(headings[i].id);
        permalink.setAttribute("aria-label", "Permalink to " + headings[i].textContent.trim());
        permalink.textContent = "✦";
        headings[i].appendChild(permalink);
    }

    var constellation = document.querySelector(".theme-constellation");
    if (!constellation) return;

    constellation.hidden = false;
    updateThemeControls(storedTheme || "{{ site.default_scheme }}");

    var buttons = constellation.querySelectorAll("[data-scheme]");
    for (var j = 0; j < buttons.length; j++) {
        buttons[j].addEventListener("click", function () {
            setTheme(this.getAttribute("data-scheme"));
        });
    }
});
