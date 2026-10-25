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

/*
  Firefox and chromium have two different quirks regarding dynamic favicons.

  Firefox does not support media queries in <link>, so we need to use @media inside style inside the svg instead.
  Chromium supports both query locations, but it rasterizes the svg upon loading it, so it doesn't switch modes without a reload.

  To satisfy both: we make a svg with @media query inside, and put that same-ish (just a space to cache bust) SVG in two different <link> with dark/light media queries.
*/
function updateFavicon(scheme) {
    var colors = schemes[scheme];
    if (!colors) return;

    var svg = encodeURIComponent(`
      <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'>
        <style>
          path {fill: ${colors.light};}
          @media (prefers-color-scheme: dark) {
            path {fill: ${colors.dark};}
          }
        </style>
        <path d='M16,1L21,11L31,16L21,21L16,31L11,21L1,16L11,11Z'/>
      </svg>
    `.replace(/\s+/g, " ").replace(/>\s+</g, "><").trim());
    setFavicon("(prefers-color-scheme: dark)", "data:image/svg+xml, " + svg);
    setFavicon("(prefers-color-scheme: light)", "data:image/svg+xml," + svg);
}

function setTheme(scheme) {
    if (schemeNames.indexOf(scheme) < 0) return;

    document.documentElement.setAttribute("data-scheme", scheme);

    updateThemeControls(scheme);
    updateFavicon(scheme);
    try {
        localStorage.setItem("fontes_theme", scheme);
    } catch (error) {
        // Switching still works when storage is unavailable or full.
    }
}

function resetTheme() {
    document.documentElement.removeAttribute("data-scheme");
    updateThemeControls("{{ site.default_scheme }}");
    updateFavicon("{{ site.default_scheme }}");

    try {
        localStorage.removeItem("fontes_theme");
    } catch (error) {
        // Resetting still works for this page when storage is unavailable.
    }
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
