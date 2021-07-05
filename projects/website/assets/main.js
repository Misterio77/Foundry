// ==== Handles ====
let scheme_options = document.getElementById("scheme-list").getElementsByTagName("option");
let scheme_button = document.getElementById("scheme-button");
let scheme_dialog = document.getElementById("scheme-dialog");
let scheme_dialog_close = document.getElementById("scheme-close");
let scheme_input = document.getElementById("scheme-input");
let scheme_default_button = document.getElementById("scheme-default");
let scheme_random_button = document.getElementById("scheme-random");

// ==== Restore scheme ====
// Get stored scheme from localStorage
if (stored_scheme) {
  scheme_input.value = stored_scheme;
  scheme_default_button.classList.remove("hidden");
}

// ==== Register listeners ====
// Register showModal to scheme-button
scheme_button.addEventListener("click", function () {
  // Additionaly, add placeholder depending on browser preference
  if (
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  ) {
    scheme_input.setAttribute("placeholder", "rose-pine-moon");
  } else {
    scheme_input.setAttribute("placeholder", "rose-pine-dawn");
  }
  // Add polyfill if showModal is not supported
  if (typeof scheme_dialog.showModal !== "function") {
    dialogPolyfill.registerDialog(scheme_dialog);
  }
  scheme_dialog.showModal();
  scheme_input.focus();
});

// Register click event for close button
scheme_dialog_close.addEventListener("click", function () {
  // Close dialog
  scheme_dialog.close();
});

// Add click event for clear button
scheme_default_button.addEventListener("click", function () {
  // Hide it
  scheme_default_button.classList.add("hidden");
  // Reset default scheme
  resetTheme();
  // Clear input
  scheme_input.value = "";
});

// Add click event to random button
scheme_random_button.addEventListener("click", function () {
  // Unhide clear button
  scheme_default_button.classList.remove("hidden");
  // Get random scheme
  let scheme = scheme_options.item(Math.floor(Math.random() * scheme_options.length)).textContent;
  // Apply it
  setTheme(scheme);
  // Set input
  scheme_input.value = scheme;
});

// Save scheme when input is changed
scheme_input.addEventListener("input", function () {
  let input = scheme_input.value;
  // If there's something on input
  if (input) {
    // Unhide clear button
    scheme_default_button.classList.remove("hidden");
    // Set scheme
    setTheme(input);
  } else {
    // Hide clear button
    scheme_default_button.classList.add("hidden");
    // Reset scheme
    resetTheme();
  }
});
