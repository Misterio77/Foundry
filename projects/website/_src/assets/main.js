---
layout: null
---

// Only favicon colors are needed in JS; palette declarations live in CSS.
var schemes = {
    {% for scheme in site.data.colorscheme %}
    "{{ scheme[0] }}": {
        dark: "{{ scheme[1].colors.dark.primary }}",
        light: "{{ scheme[1].colors.light.primary }}"
    }{% unless forloop.last %},{% endunless %}
    {% endfor %}
};
var schemeNames = Object.keys(schemes);
var starPath = "M16,1L21,11L31,16L21,21L16,31L11,21L1,16L11,11Z";

// One icon per colour scheme, matching the markup in favicon.html.liquid: a
// favicon URL is rasterised once and cached, so each mode needs its own URL
// rather than one URL expected to render two ways.
function faviconUri(color) {
    var svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'>" +
        "<path fill='" + color + "' d='" + starPath + "'/></svg>";
    return "data:image/svg+xml," + encodeURIComponent(svg);
}

function setFavicon(media, href) {
    var link = document.querySelector(media
        ? "link[rel='icon'][media='" + media + "']"
        : "link[rel='icon']:not([media])");
    if (!link) {
        link = document.createElement("link");
        link.setAttribute("rel", "icon");
        if (media) link.setAttribute("media", media);
        document.head.appendChild(link);
    }
    link.setAttribute("href", href);
}

function updateFavicon(scheme) {
    var colors = schemes[scheme];
    if (!colors) return;

    setFavicon(null, faviconUri(colors.dark));
    setFavicon("(prefers-color-scheme: light)", faviconUri(colors.light));
}

function setCookie(name, value, days) {
    var expires = "";
    if (days) {
        var date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; Expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + encodeURIComponent(value) + expires + "; Path=/; SameSite=Lax";
}

function eraseCookie(name) {
    document.cookie = name + "=; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Path=/; SameSite=Lax";
}

function setTheme(scheme) {
    if (schemeNames.indexOf(scheme) < 0) return;

    document.documentElement.setAttribute("data-scheme", scheme);

    updateThemeControls(scheme);
    updateFavicon(scheme);
    setCookie("fontes_theme", scheme, 365);
}

function resetTheme() {
    document.documentElement.removeAttribute("data-scheme");
    eraseCookie("fontes_theme");

    updateThemeControls("{{ site.default_scheme }}");
    updateFavicon("{{ site.default_scheme }}");
}

function updateThemeControls(scheme) {
    var buttons = document.querySelectorAll("button[data-scheme]");
    for (var i = 0; i < buttons.length; i++) {
        var active = buttons[i].getAttribute("data-scheme") === scheme;
        buttons[i].setAttribute("aria-pressed", active ? "true" : "false");
    }
}

// The inline head script has already restored the palette before first paint.
var storedTheme = document.documentElement.getAttribute("data-scheme");
if (storedTheme) updateFavicon(storedTheme);

document.addEventListener("DOMContentLoaded", function () {
    var headings = document.querySelectorAll("main :is(h2, h3, h4, h5, h6)[id]");
    for (var i = 0; i < headings.length; i++) {
        var permalink = document.createElement("a");
        permalink.className = "heading-permalink";
        permalink.href = "#" + encodeURIComponent(headings[i].id);
        permalink.setAttribute("aria-label", "Permalink to " + headings[i].textContent.trim());
        permalink.textContent = "#";
        headings[i].appendChild(permalink);
    }

    var constellation = document.querySelector(".theme-constellation");
    if (!constellation) return;

    constellation.hidden = false;
    updateThemeControls(storedTheme || "{{ site.default_scheme }}");

    var buttons = constellation.querySelectorAll("button[data-scheme]");
    for (var j = 0; j < buttons.length; j++) {
        buttons[j].addEventListener("click", function () {
            setTheme(this.getAttribute("data-scheme"));
        });
    }
});
