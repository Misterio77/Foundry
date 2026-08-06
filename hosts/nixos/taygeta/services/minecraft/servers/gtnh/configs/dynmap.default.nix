# Default dynmap config
{
  allow-symlinks = true;
  block-id-alias = null;
  check-banned-ips = true;
  compass-mode = "newnorth";
  components = [
    { class = "org.dynmap.ClientConfigurationComponent"; }
    {
      allowwebchat = true;
      block-banned-player-chat = true;
      chatlengthlimit = 256;
      class = "org.dynmap.InternalClientUpdateComponent";
      hide-if-invisiblity-potion = true;
      hideifsneaking = false;
      hidenames = false;
      hidewebchatip = false;
      includehiddenplayers = false;
      protected-player-info = false;
      require-player-login-ip = false;
      sendhealth = true;
      sendposition = true;
      trustclientname = false;
      use-name-colors = false;
      use-player-login-ip = true;
      webchat-interval = 5;
      webchat-permissions = false;
      webchat-requires-login = false;
    }
    {
      allowchat = true;
      allowurlname = false;
      class = "org.dynmap.SimpleWebChatComponent";
    }
    {
      class = "org.dynmap.MarkersComponent";
      default-sign-set = "markers";
      enablesigns = false;
      maxofflinetime = 30;
      offlinehidebydefault = true;
      offlineicon = "offlineuser";
      offlinelabel = "Offline";
      offlineminzoom = 0;
      showlabel = false;
      showofflineplayers = false;
      showspawn = true;
      showspawnbeds = false;
      spawnbedformat = "%name%'s bed";
      spawnbedhidebydefault = true;
      spawnbedicon = "bed";
      spawnbedlabel = "Spawn Beds";
      spawnbedminzoom = 0;
      spawnicon = "world";
      spawnlabel = "Spawn";
      type = "markers";
    }
    {
      allowurlname = false;
      class = "org.dynmap.ClientComponent";
      type = "chat";
    }
    {
      class = "org.dynmap.ClientComponent";
      focuschatballoons = false;
      type = "chatballoon";
    }
    {
      class = "org.dynmap.ClientComponent";
      messagettl = 5;
      sendbutton = false;
      showplayerfaces = true;
      type = "chatbox";
    }
    {
      class = "org.dynmap.ClientComponent";
      hidebydefault = false;
      label = "Players";
      layerprio = 0;
      showplayerbody = false;
      showplayerfaces = true;
      showplayerhealth = true;
      smallplayerfaces = false;
      type = "playermarkers";
    }
    {
      class = "org.dynmap.ClientComponent";
      type = "link";
    }
    {
      class = "org.dynmap.ClientComponent";
      showdigitalclock = true;
      type = "timeofdayclock";
    }
    {
      class = "org.dynmap.ClientComponent";
      hidey = false;
      label = "Location";
      show-mcr = false;
      type = "coord";
    }
  ];
  correct-water-lighting = true;
  ctm-support = true;
  custom-colors-support = true;
  cyrillic-support = false;
  defaultmap = "flat";
  defaultworld = "world";
  defaultzoom = 0;
  deftemplatesuffix = "hires";
  disable-webserver = false;
  display-whitelist = false;
  dump-missing-blocks = false;
  enabletilehash = true;
  exportpath = "export";
  fullrender-min-tps = 18;
  fullrenderplayerlimit = 0;
  grayplayerswhenhidden = true;
  image-format = "png";
  initial-zoomout-validate = true;
  joinmessage = "%playername% joined";
  login-enabled = false;
  login-required = false;
  max-sessions = 30;
  maxchunkspertick = 200;
  msg = {
    chatnotallowed = "You are not permitted to send chat messages";
    chatrequireslogin = "Chat Requires Login";
    hiddennamejoin = "Player joined";
    hiddennamequit = "Player quit";
    maptypes = "Map Types";
    players = "Players";
  };
  per-tick-time-limit = 50;
  persist-ids-by-ip = true;
  progressloginterval = 100;
  quitmessage = "%playername% quit";
  render-triggers = [
    "blockupdate"
    "chunkpopulate"
    "chunkgenerate"
  ];
  renderaccelerateinterval = 0.2;
  renderacceleratethreshold = 60;
  renderinterval = 1;
  save-pending-period = 900;
  saverestorepending = true;
  showlayercontrol = true;
  showplayerfacesinmenu = true;
  skin-url = "http://skins.minecraft.net/MinecraftSkins/%player%.png";
  smooth-lighting = true;
  snapshotcachesize = 500;
  soft-ref-cache = true;
  spammessage = "You may only chat once every %interval% seconds.";
  spout = {
    enabled = true;
    use-existing-textures = true;
  };
  storage = {
    type = "filetree";
  };
  tiles-rendered-at-once = 2;
  tilespath = "web/tiles";
  tileupdatedelay = 30;
  timesliceinterval = 0;
  transparent-leaves = true;
  trusted-proxies = [
    "127.0.0.1"
    "0:0:0:0:0:0:0:1"
  ];
  update-min-tps = 18;
  updateplayerlimit = 0;
  updaterate = 2000;
  url = null;
  use-brightness-table = true;
  use-generated-textures = true;
  usenormalthreadpriority = true;
  verbose = false;
  webmsgformat = "&color;2[WEB] %playername%: &color;f%message%";
  webpath = "web";
  webserver-port = 8123;
  zoomout-min-tps = 18;
  zoomoutperiod = 30;
}
