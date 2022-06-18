let chosen_scheme_css = document.getElementById("scheme-css");

// Set a given scheme
function setTheme(scheme) {
    chosen_scheme_css.setAttribute(
        "href",
        "/assets/themes/" + scheme + ".css"
    );
    localStorage.setItem("current-scheme", scheme);
}

// Get currently applied scheme
function getTheme() {
    let theme = localStorage.getItem("current-scheme");
    if (theme != "null") {
        return theme;
    } else {
        return null;
    }
}

// Reset scheme to default
function resetTheme() {
    chosen_scheme_css.removeAttribute("href");
    localStorage.removeItem("current-scheme");
}

// Get stored scheme from localStorage and reapply it
let stored = getTheme();
if (stored) {
    setTheme(stored);
}
