{
  description = "jsonfly";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, utils, ... } @ inputs: 
    utils.lib.eachDefaultSystem(system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        logo = pkgs.writeText "logo.txt" ''
     ▄█    ▄████████  ▄██████▄  ███▄▄▄▄      ▄████████  ▄█       ▄██   ▄   
    ███   ███    ███ ███    ███ ███▀▀▀██▄   ███    ███ ███       ███   ██▄ 
    ███   ███    █▀  ███    ███ ███   ███   ███    █▀  ███       ███▄▄▄███ 
    ███   ███        ███    ███ ███   ███  ▄███▄▄▄     ███       ▀▀▀▀▀▀███ 
    ███ ▀███████████ ███    ███ ███   ███ ▀▀███▀▀▀     ███       ▄██   ███ 
    ███          ███ ███    ███ ███   ███   ███        ███       ███   ███ 
    ███    ▄█    ███ ███    ███ ███   ███   ███        ███▌    ▄ ███   ███ 
█▄ ▄███  ▄████████▀   ▀██████▀   ▀█   █▀    ███        █████▄▄██  ▀█████▀  
▀▀▀▀▀▀                                                 ▀                   
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            stylua

            # If this ever fails, just remove it. It's just for the logo.
            lolcat
          ];

          shellHook = ''
            cat ${logo} | lolcat
            echo "";
            echo "Welcome to the jsonfly.nvim development environment!";
            echo "";
          '';
        };
      }
    );
}
