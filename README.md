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

## License

Released into the public domain. Modify and distribute freely.[^1]

[^1]: This part was added by the AI inside its totally slop README and I'm keeping it because it's funny. But really, it's a shell script, who cares. View the Git log if you wanna see the original README slop
