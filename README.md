## Experimental Channel

This is the **experimental** channel.  
Here, we actively optimize the driver and push performance as close to the theoretical limits as possible, without intentionally introducing harmful regressions.  
Use this channel if you:

- are comfortable with **heavy testing and debugging**,  
- want to **maximize speed and stability** under extreme conditions,  
- and do **not** rely on the system for production use.

This branch may receive frequent, disruptive changes and is **not recommended for daily use**.


## RTL8821CU Driver for Linux (KDE, Kubuntu, latest Kernel)

This fork is **actively maintained** and currently under active development.
The goal is to keep the `rtl8821CU` driver compatible with modern kernels (including recent KDE and Ubuntu-based distributions like Kubuntu).

If you are affected by build issues, missing modules, or broken 5 GHz support,
please open an **Issue** with:
- your kernel version,
- your distribution,
- the full `dmesg` or `make.log` output.

Contributions are welcome.  
Thanks to the original project `brektrou/rtl8821CU` for the base code.
