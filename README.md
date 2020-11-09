# dell-csi-static-pv
This repo contains a script to ease static PV provisioning with DellEMC Drivers

The script contains:
* checks to make sure the volume handle is compatible with the driver constructions
* documentation of the volume handle construction (e.g. `STORAGECLASS=powermax VOLUMEHANDLE=help`)

The script creates a PersistentVolume and optionnaly a related PersistentVolumeClaim for the given parameters.

The `ingest-static-pv.sh` parameters are entirely driven by environment variables (see `./ingest-static-pv.sh` for more details)


It supports [PowerMax](https://github.com/dell/csi-powermax), [PowerStore](https://github.com/dell/csi-powerstore), [PowerScale](https://github.com/dell/csi-powerscale), [PowerFlex](https://github.com/dell/csi-vxflexos), and [Unity](https://github.com/dell/csi-unity).

You can find more details about the script usage and `volumeHandle` crafting for DellEMC drivers on https://storage-chaos.io/pv-static-provisioning.html
