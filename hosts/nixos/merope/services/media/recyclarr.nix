{config, ...}: {
  services.recyclarr = {
    enable = true;
    configuration = {
      sonarr.main-sonarr = {
        api_key._secret = config.sops.secrets.sonarr-key.path;
        base_url = "http://localhost:${toString config.services.sonarr.settings.server.port}";
        delete_old_custom_formats = true;
        replace_existing_custom_formats = true;
        quality_definitions = {
          # Use anime quality definition (i.e. prefer smaller sizes)
          type = "anime";
        };
        quality_profiles = [
          {
            name = "WEB-1080p";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "WEB 1080p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              { name = "WEB 1080p"; qualities = [ "WEBDL-1080p" "WEBRip-1080p" ]; }
              { name = "Bluray-1080p"; }
              { name = "HDTV-1080p"; }
              { name = "WEB 720p"; qualities = [ "WEBDL-720p" "WEBRip-720p" ]; }
              { name = "Bluray-720p"; }
              { name = "HDTV-720p"; }
            ];
          }
          {
            name = "Remux-1080p - Anime";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 10000;
            };
            min_format_score = 100;
            quality_sort = "top";
            score_set = "anime-sonarr";
            qualities = [
              { name = "Bluray-1080p"; qualities = [ "Bluray-1080p Remux" "Bluray-1080p" ]; }
              { name = "WEB 1080p"; qualities = [ "WEBDL-1080p" "WEBRip-1080p" "HDTV-1080p" ]; }
              { name = "Bluray-720p"; }
              { name = "WEB 720p"; qualities = [ "WEBDL-720p" "WEBRip-720p" "HDTV-720p" ]; }
              { name = "Bluray-480p"; }
              { name = "WEB 480p"; qualities = [ "WEBDL-480p" "WEBRip-480p" ]; }
              { name = "DVD"; }
              { name = "SDTV"; }
            ];
          }
        ];
        custom_formats = [
          {
            assign_scores_to = [{ name = "WEB-1080p"; }];
            trash_ids = [
              # Unwanted
              "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
              "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
              "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
              "47435ece6b99a0b477caf360e79ba0bb" # x265 (HD)
              "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
              "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
              # Misc
              "ec8fa7296b64e8cd390a1600981f3923" # Repack/Proper
              "eb3d5cc0a2be0db205fb823640db6a3c" # Repack v2
              "44e7c4de10ae50265753082e5dc76047" # Repack v3
              # Streaming Services
              "d660701077794679fd59e8bdf4ce3a29" # AMZN
              "f67c9ca88f463a48346062e8ad07713f" # ATVP
              "77a7b25585c18af08f60b1547bb9b4fb" # CC
              "36b72f59f4ea20aad9316f475f2d9fbb" # DCU
              "dc5f2bb0e0262155b5fedd0f6c5d2b55" # DSCP
              "89358767a60cc28783cdc3d0be9388a4" # DSNP
              "7a235133c87f7da4c8cccceca7e3c7a6" # HBO
              "a880d6abc21e7c16884f3ae393f84179" # HMAX
              "f6cce30f1733d5c8194222a7507909bb" # Hulu
              "0ac24a2a68a9700bcb7eeca8e5cd644c" # iT
              "81d1fbf600e2540cee87f3a23f9d3c1c" # MAX
              "d34870697c9db575f17700212167be23" # NF
              "1656adc6d7bb2c8cca6acfb6592db421" # PCOK
              "c67a75ae4a1715f2bb4d492755ba4195" # PMTP
              "ae58039e1319178e6be73caab5c42166" # SHO
              "1efe8da11bfd74fbbcd4d8117ddb9213" # STAN
              "9623c5c9cac8e939c1b9aedd32f640bf" # SYFY
              "218e93e5702f44a68ad9e3c6ba87d2f0" # HD Streaming Boost
              # HQ Source Groups
              "e6258996055b9fbab7e9cb2f75819294" # WEB Tier 01
              "58790d4e2fdcd9733aa7ae68ba2bb503" # WEB Tier 02
              "d84935abd3f8556dcd51d4f27e22d0a6" # WEB Tier 03
              "d0c516558625b04b363fa6c5c2c7cfd4" # WEB Scene
            ];
          }
          {
            assign_scores_to = [{ name = "Remux-1080p - Anime"; }];
            trash_ids = [
              # Anime CF/Scoring
              "949c16fe0a8147f50ba82cc2df9411c9" # Anime BD Tier 01 (Top SeaDex Muxers)
              "ed7f1e315e000aef424a58517fa48727" # Anime BD Tier 02 (SeaDex Muxers)
              "096e406c92baa713da4a72d88030b815" # Anime BD Tier 03 (SeaDex Muxers)
              "30feba9da3030c5ed1e0f7d610bcadc4" # Anime BD Tier 04 (SeaDex Muxers)
              "545a76b14ddc349b8b185a6344e28b04" # Anime BD Tier 05 (Remuxes)
              "25d2afecab632b1582eaf03b63055f72" # Anime BD Tier 06 (FanSubs)
              "0329044e3d9137b08502a9f84a7e58db" # Anime BD Tier 07 (P2P/Scene)
              "c81bbfb47fed3d5a3ad027d077f889de" # Anime BD Tier 08 (Mini Encodes)
              "e0014372773c8f0e1bef8824f00c7dc4" # Anime Web Tier 01 (Muxers)
              "19180499de5ef2b84b6ec59aae444696" # Anime Web Tier 02 (Top FanSubs)
              "c27f2ae6a4e82373b0f1da094e2489ad" # Anime Web Tier 03 (Official Subs)
              "4fd5528a3a8024e6b49f9c67053ea5f3" # Anime Web Tier 04 (Official Subs)
              "29c2a13d091144f63307e4a8ce963a39" # Anime Web Tier 05 (FanSubs)
              "dc262f88d74c651b12e9d90b39f6c753" # Anime Web Tier 06 (FanSubs)
              "e3515e519f3b1360cbfc17651944354c" # Anime LQ Groups
              "b4a1b3d705159cdca36d71e57ca86871" # Anime Raws
              "9c14d194486c4014d422adc64092d794" # Dubs Only
              "d2d7b8a9d39413da5f44054080e028a3" # v0
              "273bd326df95955e1b6c26527d1df89b" # v1
              "228b8ee9aa0a609463efca874524a6b8" # v2
              "0e5833d3af2cc5fa96a0c29cd4477feb" # v3
              "4fc15eeb8f2f9a749f918217d4234ad8" # v4
              "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
              "07a32f77690263bb9fda1842db7e273f" # VOSTFR
              # Anime Streaming Services
              "3e0b26604165f463f3e8e192261e7284" # CR
              "1284d18e693de8efe0fe7d6b3e0b9170" # FUNi
              "44a8ee6403071dd7b8a3a8dd3fe8cb20" # VRV
              "89358767a60cc28783cdc3d0be9388a4" # DSNP
              "d34870697c9db575f17700212167be23" # NF
              "d660701077794679fd59e8bdf4ce3a29" # AMZN
              "d54cd2bf1326287275b56bccedb72ee2" # ADN
              "7dd31f3dee6d2ef8eeaa156e23c3857e" # B-Global
              "4c67ff059210182b59cdd41697b8cb08" # Bilibili
              "570b03b3145a25011bf073274a407259" # HIDIVE
              "a370d974bc7b80374de1d9ba7519760b" # ABEMA
              # Main Guide Remux Tier Scoring
              "9965a052eb87b0d10313b1cea89eb451" # Remux Tier 01
              "8a1d0c3d7497e741736761a1da866a2e" # Remux Tier 02
              # Main Guide WEB Tier Scoring
              "e6258996055b9fbab7e9cb2f75819294" # WEB Tier 01
              "58790d4e2fdcd9733aa7ae68ba2bb503" # WEB Tier 02
              "d84935abd3f8556dcd51d4f27e22d0a6" # WEB Tier 03
            ];
          }
        ];
      };
      radarr.main-radarr = {
        api_key._secret = config.sops.secrets.radarr-key.path;
        base_url = "http://localhost:${toString config.services.radarr.settings.server.port}";
        delete_old_custom_formats = true;
        replace_existing_custom_formats = true;
        quality_definitions = {
          # Use anime quality definition (i.e. prefer smaller sizes)
          type = "anime";
        };
        quality_profiles = [
          {
            name = "Remux-1080p - Anime";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Remux-1080p";
              until_score = 10000;
            };
            min_format_score = 100;
            score_set = "anime-radarr";
            quality_sort = "top";
            qualities = [
              { name = "Remux-1080p"; qualities = [ "Bluray-1080p" "Remux-1080p" ]; }
              { name = "WEB 1080p"; qualities = [ "WEBDL-1080p" "WEBRip-1080p" "HDTV-1080p" ]; }
              { name = "Bluray-720p"; }
              { name = "WEB 720p"; qualities = [ "WEBDL-720p" "WEBRip-720p" "HDTV-720p" ]; }
              { name = "Bluray-576p"; }
              { name = "Bluray-480p"; }
              { name = "WEB 480p"; qualities = [ "WEBDL-480p" "WEBRip-480p" ]; }
              { name = "DVD"; }
              { name = "SDTV"; }
            ];
          }
          {
            name = "HD Bluray + WEB";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              { name = "Bluray-1080p"; }
              { name = "WEB 1080p"; qualities = [ "WEBDL-1080p" "WEBRip-1080p" ]; }
              { name = "Bluray-720p"; }
            ];
          }
          {
            # (VF means "I want multiple (original+french), fallback to only french if multi is not available")
            name = "FR-MULTi-VF-HD";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray|WEB 1080p";
              until_score = 10000;
            };
            min_format_score = 0;
            score_set = "french-multi-vf";
            quality_sort = "top";
            qualities = [
              { name = "Bluray|WEB 1080p"; qualities = [ "Bluray-1080p" "WEBDL-1080p" "WEBRip-1080p" ]; }
              { name = "Bluray-720p"; }
            ];
          }
        ];
        custom_formats = [
          {
            assign_scores_to = [{ name = "Remux-1080p - Anime"; }];
            trash_ids = [
              # Anime CF/Scoring
              "fb3ccc5d5cc8f77c9055d4cb4561dded" # Anime BD Tier 01 (Top SeaDex Muxers)
              "66926c8fa9312bc74ab71bf69aae4f4a" # Anime BD Tier 02 (SeaDex Muxers)
              "fa857662bad28d5ff21a6e611869a0ff" # Anime BD Tier 03 (SeaDex Muxers)
              "f262f1299d99b1a2263375e8fa2ddbb3" # Anime BD Tier 04 (SeaDex Muxers)
              "ca864ed93c7b431150cc6748dc34875d" # Anime BD Tier 05 (Remuxes)
              "9dce189b960fddf47891b7484ee886ca" # Anime BD Tier 06 (FanSubs)
              "1ef101b3a82646b40e0cab7fc92cd896" # Anime BD Tier 07 (P2P/Scene)
              "6115ccd6640b978234cc47f2c1f2cadc" # Anime BD Tier 08 (Mini Encodes)
              "8167cffba4febfb9a6988ef24f274e7e" # Anime Web Tier 01 (Muxers)
              "8526c54e36b4962d340fce52ef030e76" # Anime Web Tier 02 (Top FanSubs)
              "de41e72708d2c856fa261094c85e965d" # Anime Web Tier 03 (Official Subs)
              "9edaeee9ea3bcd585da9b7c0ac3fc54f" # Anime Web Tier 04 (Official Subs)
              "22d953bbe897857b517928f3652b8dd3" # Anime Web Tier 05 (FanSubs)
              "a786fbc0eae05afe3bb51aee3c83a9d4" # Anime Web Tier 06 (FanSubs)
              "b0fdc5897f68c9a68c70c25169f77447" # Anime LQ Groups
              "c259005cbaeb5ab44c06eddb4751e70c" # v0
              "5f400539421b8fcf71d51e6384434573" # v1
              "3df5e6dfef4b09bb6002f732bed5b774" # v2
              "db92c27ba606996b146b57fbe6d09186" # v3
              "d4e5e842fad129a3c097bdb2d20d31a0" # v4
              "06b6542a47037d1e33b15aa3677c2365" # Anime Raws
              "9172b2f683f6223e3a1846427b417a3d" # VOSTFR
              "b23eae459cc960816f2d6ba84af45055" # Dubs Only
              # Anime Streaming Services
              "60f6d50cbd3cfc3e9a8c00e3a30c3114" # VRV
              # Main Guide Remux Tier Scoring
              "3a3ff47579026e76d6504ebea39390de" # Remux Tier 01
              "9f98181fe5a3fbeb0cc29340da2a468a" # Remux Tier 02
              "8baaf0b3142bf4d94c42a724f034e27a" # Remux Tier 03
              # Main Guide WEB Tier Scoring
              "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
              "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
              "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03
            ];
          }
          {
            assign_scores_to = [{ name = "HD Bluray + WEB"; }];
            trash_ids = [
              # HQ Release Groups
              "ed27ebfef2f323e964fb1f61391bcb35" # HD Bluray Tier 01
              "c20c8647f2746a1f4c4262b0fbbeeeae" # HD Bluray Tier 02
              "5608c71bcebba0a5e666223bae8c9227" # HD Bluray Tier 03
              "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
              "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
              "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03
              # Misc
              "e7718d7a3ce595f289bfee26adc178f5" # Repack/Proper
              "ae43b294509409a6a13919dedd4764c4" # Repack2
              "5caaaa1c08c1742aa4342d8c4cc463f2" # Repack3
              # Unwanted
              "ed38b889b31be83fda192888e2286d83" # BR-DISK
              "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
              "90a6f9a284dff5103f6346090e6280c8" # LQ
              "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
              "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
              "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
              "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
              "0a3f082873eb454bde444150b70253cc" # Extras
              "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
              "cae4ca30163749b891686f95532519bd" # AV1
              # Streaming Services
              "cc5e51a9e85a6296ceefe097a77f12f4" # BCORE
              "16622a6911d1ab5d5b8b713d5b0036d4" # CRiT
              "2a6039655313bf5dab1e43523b62c374" # MA
            ];
          }
          {
            assign_scores_to = [{ name = "HD Bluray + WEB"; }];
            trash_ids = [
              # Streaming Services
              "b3b3a6ac74ecbd56bcdbefa4799fb9df" # AMZN
              "40e9380490e748672c2522eaaeb692f7" # ATVP
              "84272245b2988854bfb76a16e60baea5" # DSNP
              "509e5f41146e278f9eab1ddaceb34515" # HBO
              "5763d1b0ce84aff3b21038eea8e9b8ad" # HMAX
              "526d445d4c16214309f0fd2b3be18a89" # Hulu
              "e0ec9672be6cac914ffad34a6b077209" # iT
              "6a061313d22e51e0f25b7cd4dc065233" # MAX
              "170b1d363bd8516fbf3a3eb05d4faff6" # NF
              "c9fd353f8f5f1baf56dc601c4cb29920" # PCOK
              "e36a0ba1bc902b26ee40818a1d59b8bd" # PMTP
              "c2863d2a50c9acad1fb50e53ece60817" # STAN
            ];
          }
          {
            assign_scores_to = [{ name = "FR-MULTi-VF-HD"; }];
            trash_ids = [
              # Language CFs
              "d6e9318c875905d6cfb5bee961afcea9" # Language: Not Original
              "533f782474f0819643c2ec0c1eeeb0ac" # Language: Not French
              "0542a48746585dc4444bbbb8a6bdf6ea" # Language: Original + French
              "4b900e171accbfb172729b63323ea8ca" # MULTi
              # FR HQ Source Groups
              "5322da05b19d857acc1e75be3edf47b3" # FR HD Bluray Tier 01
              "57f34251344be2e283fc30e00e458be6" # FR HD Bluray Tier 02
              "9790a618cec1aeac8ce75601a17ea40d" # FR WEB Tier 01
              "3c83a765f84239716bd5fd2d7af188f9" # FR WEB Tier 02
              "0d94489c0d5828cd3bf9409d309fb32b" # FR Scene Groups
              # Misc
              "e7718d7a3ce595f289bfee26adc178f5" # Repack/Proper
              "ae43b294509409a6a13919dedd4764c4" # Repack2
              "5caaaa1c08c1742aa4342d8c4cc463f2" # Repack3
              # Unwanted
              "ed38b889b31be83fda192888e2286d83" # BR-DISK
              "90a6f9a284dff5103f6346090e6280c8" # LQ
              "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
              "48f031e76111f17ea94898f4cdc34fdc" # FR LQ
              "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
              "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
              "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
              "0a3f082873eb454bde444150b70253cc" # Extras
              "cae4ca30163749b891686f95532519bd" # AV1
              # Streaming Services
              "cc5e51a9e85a6296ceefe097a77f12f4" # BCORE
              "16622a6911d1ab5d5b8b713d5b0036d4" # CRiT
              "2a6039655313bf5dab1e43523b62c374" # MA
            ];
          }
          {
            assign_scores_to = [{ name = "FR-MULTi-VF-HD"; score = 0; }];
            trash_ids = [
              # Streaming Services
              "b3b3a6ac74ecbd56bcdbefa4799fb9df" # AMZN
              "40e9380490e748672c2522eaaeb692f7" # ATVP
              "84272245b2988854bfb76a16e60baea5" # DSNP
              "509e5f41146e278f9eab1ddaceb34515" # HBO
              "5763d1b0ce84aff3b21038eea8e9b8ad" # HMAX
              "526d445d4c16214309f0fd2b3be18a89" # Hulu
              "e0ec9672be6cac914ffad34a6b077209" # iT
              "6a061313d22e51e0f25b7cd4dc065233" # MAX
              "170b1d363bd8516fbf3a3eb05d4faff6" # NF
              "c9fd353f8f5f1baf56dc601c4cb29920" # PCOK
              "e36a0ba1bc902b26ee40818a1d59b8bd" # PMTP
              "c2863d2a50c9acad1fb50e53ece60817" # STAN
            ];
          }
        ];
      };
    };
  };

  sops.secrets = {
    sonarr-key = {
      sopsFile = ../../secrets.yaml;
      owner = config.services.recyclarr.user;
      group = config.services.recyclarr.group;
    };
    radarr-key = {
      sopsFile  = ../../secrets.yaml;
      owner = config.services.recyclarr.user;
      group = config.services.recyclarr.group;
    };
  };
}
