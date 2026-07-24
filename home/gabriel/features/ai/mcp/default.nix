{...}: {
  programs.mcp = {
    enable = true;
    servers.osrs = {
      url = "http://127.0.0.1:18471/mcp";
      lifecycle = "lazy";
    };
  };
}
