# sudo-run0

Simple wrapper around systemd's run0 that emulates and provides compatibility
with some Sudo options.

(Mostly) AI-generated because writing 400 line shell scripts is no fun. But it
should be fine as all it does is wrap run0.

If you are really paranoid about it being AI-written, there are a few lines in
the script you can uncomment that will show the run0 command line before it's
invoked, and even pause and wait for confirmation if you so wish. Or you could,
just, you know... use run0 directly.

## Dependencies

Systemd. Bash. Coreutils. Util-linux. Glibc (for `getent`). That's it.

> All of these are very standard utilities that would be present on virtually
> any Linux system by default. The script doesn't appear to have any unusual or
> special dependencies beyond these basic system utilities.
>                                                        *-- claude-3.5-sonnet*

## NixOS Module

If you want to use this in NixOS, this repo is a flake that provides the
`sudo-run0` module. The module will force Polkit to be enabled, and throw an
assertion if it ever gets disabled to prevent accidentally locking yourself out
(this has happened to me before; you're welcome).

By default, it will disable Sudo and add itself to the system path. The module
is controlled by the built-in NixOS option `security.sudo.enable` -- if Sudo is
enabled, this wrapper will be disabled, and vice-versa. If you ever wish to
re-enable Sudo, just set that option to true.

Example usage:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sudo-run0 = {
      url = "github:andre4ik3/sudo-run0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      modules = [
        # ... other modules ...
        sudo-run0.nixosModules.sudo-run0
        # ... other modules ...
      ];
    };
  };
}
```

## License

Released into the public domain. Modify and distribute freely.[^1]

[^1]: This part was added by the AI inside its totally slop README and I'm keeping it because it's funny. But really, it's a shell script, who cares. View the Git log if you wanna see the original README slop
