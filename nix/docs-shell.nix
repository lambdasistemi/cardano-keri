let
  shared = builtins.getFlake "github:paolino/dev-assets/a9d7371c1118de4026ba6ee3a9c3b54614924b82?dir=mkdocs";
  pkgs = shared.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  terminal = pkgs.python3Packages.buildPythonPackage {
    pname = "mkdocs-terminal";
    version = "4.8.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/cd/21/7eb37356eeeaa87be873c806ea84794b3b81285e49a6c7c4a250c66729a6/mkdocs_terminal-4.8.0-py3-none-any.whl";
      sha256 = "86af80cc7152aa61e9058db0a84eefae56e769222e81eb5291ad87e89d3f2922";
    };
    dependencies = with pkgs.python3Packages; [ jinja2 markdown mkdocs pygments pymdown-extensions ];
  };
in
shared.devShells.${builtins.currentSystem}.default.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [ terminal ];
})
