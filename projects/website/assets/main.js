let chosen_scheme_css = document.getElementById("scheme-css");
let scheme_input = document.getElementById("scheme-input");

// Set a given scheme
function setTheme(scheme) {
    chosen_scheme_css.setAttribute(
        "href",
        "/assets/themes/" + scheme + ".css"
    );
    scheme_input.value = scheme;
    localStorage.setItem("current-scheme", scheme);
}

// Reset scheme to defaults (rose-pine moon or dawn, depending on preference)
function resetTheme() {
    chosen_scheme_css.removeAttribute("href");
    localStorage.removeItem("current-scheme");
}

function updatePlaceholder(dark) {
    if (dark) {
        scheme_input.setAttribute("placeholder", "rose-pine-moon");
    } else {
        scheme_input.setAttribute("placeholder", "rose-pine-dawn");
    }
}

// Get stored scheme from localStorage and reapply it
let stored_scheme = localStorage.getItem("current-scheme");
if (stored_scheme) {
    setTheme(stored_scheme);
}

// Add scheme input event listener
scheme_input.addEventListener("input", function () {
  let input = scheme_input.value;
  if (input) {
    setTheme(input);
  } else {
    resetTheme();
  }
});

// Check browser color scheme
let isDark = window.matchMedia('(prefers-color-scheme: dark)').media === 'not all';
updatePlaceholder(isDark);
window.matchMedia("(prefers-color-scheme: dark)").addListener(
  e => {
      let isDark = e.matches;
      updatePlaceholder(isDark);
  }
);
