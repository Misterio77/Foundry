{pkgs, ...}: let
  json = pkgs.formats.json {};
in {
  xdg.configFile."pipewire/pipewire.conf.d/99-deepfilternet.conf" = {
    source = json.generate "deepfilternet-pipewire.conf" {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "DeepFilter Noise Canceling Source";
            "media.name" = "DeepFilter Noise Canceling Source";
            "filter.graph" = {
              nodes = [
                {
                  type = "ladspa";
                  name = "DeepFilter Mono";
                  plugin = "${pkgs.deepfilternet}/lib/ladspa/libdeep_filter_ladspa.so";
                  label = "deep_filter_mono";
                  control."Attenuation Limit (dB)" = 100.0;
                }
              ];
            };
            "audio.rate" = 48000;
            "audio.position" = ["MONO"];
            "capture.props"."node.passive" = true;
            "playback.props" = {
              "node.name" = "deepfilter_source";
              "media.class" = "Audio/Source";
            };
          };
        }
      ];
    };

    onChange = ''
      if ${pkgs.systemd}/bin/systemctl --user --quiet is-active pipewire.service; then
        ${pkgs.systemd}/bin/systemctl --user restart pipewire.service
      fi
    '';
  };
}
