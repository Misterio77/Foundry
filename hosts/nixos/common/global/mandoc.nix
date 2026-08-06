{
  documentation.man = {
    # Performance regression. See https://github.com/NixOS/nixpkgs/issues/513348
    man-db.enable = false;
    mandoc.enable = true;
  };
}
