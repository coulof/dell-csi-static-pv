#!/bin/bash
# Copyright: (c) 2020, Dell EMC
#
# TODO :
#  * Improve templating with kustomize
#  * Improve argument parsing and put default values (powermax, ext4, etc.)
#  * Support multiple AccessMode

DRYRUN=${DRYRUN-true}
STORAGECLASS=${STORAGECLASS}
PROVISIONER=${PROVISIONER}
VOLUMEHANDLE=${VOLUMEHANDLE}
ACCESSMODE=${ACCESSMODE-ReadWriteOnce}
FSTYPE=${FSTYPE-ext4}
SIZE=${SIZE}
PVNAME=${PVNAME}
PVCNAME=${PVCNAME}
NAMESPACE=${NAMESPACE-default}

usage(){
  echo -e "
\e[1mingest-static-pv.sh\e[21m helps to statically load DellEMC PersistentVolume in Kubernetes ; the configuration is driven by environment variables

Usage is:
STORAGECLASS=powermax VOLUMEHANDLE=csi-net-pmax-4a519418bd-000000000000-00000 PVNAME=pmax-a6e6012a1b SIZE=8 PVCNAME=testpvc DRYRUN=true ./ingest-static-pv.sh

  STORAGECLASS is the StorageClass of the PersistentVolume, for example: powermax, powermax-xfs, custom-powermax
  PROVISIONER is the provisioner for StorageClass if STORAGECLASS contains the driver name it will try to match it (for example, by default, it will match csi-powermax.dellemc.com)
  VOLUMEHANDLE is the key to map a PV to the backend volume
               to get the VolumeHandle construction run STORAGECLASS=powermax VOLUMEHANDLE=help ./ingest-static-pv.sh
  ACCESSMODE is the access mode for the PV either ReadWriteOnce|ReadOnlyMany|ReadWriteMany (default: ReadWriteOnce)
  PVNAME is the name of the PV, most of the time this is the name of the volume in the array but any name will do
  FSTYPE is the filesytem format or the volume mode raw, the value is either raw|ext4|xfs (default: ext4) 
  SIZE is the PV size in Gi
  PVCNAME (Optional) if that variable is set it will create the PersistentVolumeClaim to Bound the PV
  NAMESPACE is the namespace for the PVC (default: default)
  DRYRUN if \e[1mtrue\e[21m, it will call kubectl and create the PV. Any other values will only print the actions (default: false)
  "
}

check_powermax_volumehandle(){
  if ! [[ $VOLUMEHANDLE =~ ^csi-[a-zA-Z]{,3}-[a-z]*-[a-zA-Z0-9]{10}-[0-9]{12}-[a-zA-Z0-9]{5}$ ]]; then
    echo -e "\e[31m \"$VOLUMEHANDLE\" Wrong volumeHandle, check your name syntax here : \e[4mhttps://rubular.com/r/TSQDPIDss2K9Hb\e[0m"
    echo -e "
    The volumeHandle in PowerMax must be in the following format:
    csi-<Cluster Prefix>-<Volume Prefix>-<Volume Name>-<Symmetrix ID>-<Symmetrix Vol ID>
    a          b               c              d             e              f
    a. csi- is an hardcoded value
    b. Cluster Prefix, is the value given during the installation of the driver in the variable named \e[1mclusterPrefix\e[21m
    c. Volume Prefix, is the value given during the installation of the driver in the variable named \e[1mvolumeNamePrefix\e[21m
    d. Volume Name, is a random UUID given by the controller sidecar. You can that value in Unisphere.
    If you need a new UUID you can use the command \e[1muuidgen\e[21m and pick the last 10 characters
    e. Symmetrix ID is the twelve characters long PowerMax identifier
    f. Symmetrix Vol ID is the LUN identifier
      The construction of the volumeHandle is given here : \e[4mhttps://github.com/dell/csi-powermax/blob/v1.4.0/service/controller.go#L720\e[24m
    "
    exit 1
  fi
}

check_powerstore_volumehandle(){
  if ! [[ $VOLUMEHANDLE =~ ^[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}$ ]]; then
    echo -e "\e[31m \"$VOLUMEHANDLE\" Wrong volumeHandle, check your name syntax here : \e[4mhttps://rubular.com/r/7HgR3Zzn6VPMA1\e[0m"
    echo -e "
    The volumeHandle in PowerStore volume ID has given by PowerStore.
    It is a UUID, which you can find in the URL of the web interface.
    "
    exit 1
  fi
}


check_isilon_volumehandle(){
  if ! [[ $VOLUMEHANDLE =~ ^(.*)=_=_=[0-9]+=_=_=(.*)$ ]]; then
    echo -e "\e[31m \"$VOLUMEHANDLE\" Wrong volumeHandle, check your name syntax here : \e[4mhttps://rubular.com/r/4iQnXaX26sipCb\e[0m"
    echo -e "
    The volumeHandle in PowerScale/Isilon must be in the following format:
    <Volume Name>=_=_=<Export ID>=_=_=<Access Zone Name>
    "
    exit 1
  fi
}

check_vxflexos_volumehandle(){
  if ! [[ $VOLUMEHANDLE =~ ^[a-zA-Z0-9]{16}$ ]]; then
    echo -e "\e[31m \"$VOLUMEHANDLE\" Wrong volumeHandle, check your name syntax here : \e[4mhttps://rubular.com/r/aGSCIzxmwFFs5E\e[0m"
    echo -e "
    The volumeHandle in PowerFlex/VxFlexOS is the volume ID has given by PowerFlex.
    It is composed of 16 alphanumerical characters.
    "
    exit 1
  fi
}

check_unity_volumehandle(){
  if ! [[ $VOLUMEHANDLE =~ ^(.*)-(iSCSI|NFS|FC)-.*-(sv|fs)_[0-9]+$ ]]; then
    echo -e "\e[31m \"$VOLUMEHANDLE\" Wrong volumeHandle, check your name syntax here : \e[4mhttps://rubular.com/r/Cuf9BnPq7ZCEgp\e[0m"
    echo -e "
    The volumeHandle in Unity must be in the following format:
    <Volume Name>-<Protocol>-<Array ID>-<Object ID>
          a           b          c           d
    a. The volume name is composed of the \e[1mvolumeNamePrefix\e[21m given during the installation time and a 10 characters UUID given by the controller sidecar.
       You can retrieve the name from Unisphere under Block or File sections.
       a random UUID given by the controller sidecar
    b. The protocol can be iSCSI or FC or NFS
    c. The Array ID can be retrieve from Unisphere under System View.
    d. The Object ID is the Volume identifier (for Block) or Filesystem identifier. It is displayed as \e[1mCLI ID\e[21m in Unisphere tables.
    "
    exit 1
  fi
}

check_pvname(){
  if ! [[ $PVNAME =~ [a-z]*-[a-zA-Z0-9]{10} ]]; then
    echo -e "\e[31mWrong \"$PVNAME\"\e[0m
    The Volume Name, is a random UUID given by the controller sidecar. You can most probably find it from Unisphere.
    If you need a new UUID you can use the command \e[1muuidgen\e[21m and pick the last 10 characters
    "
    exit 1
  fi
}


# Try to map the provisioner
if [[ -z $PROVISIONER ]]; then
  if [[ $STORAGECLASS =~ powermax ]]; then
    PROVISIONER="csi-powermax.dellemc.com"
  elif [[ $STORAGECLASS =~ powerstore ]]; then
    PROVISIONER="csi-powerstore.dellemc.com"
  elif [[ $STORAGECLASS =~ powerscale|isilon ]]; then
    PROVISIONER="csi-isilon.dellemc.com"
  elif [[ $STORAGECLASS =~ powerflex|vxflexos|scaleio ]]; then
    PROVISIONER="csi-vxflexos.dellemc.com"
  elif [[ $STORAGECLASS =~ unity ]]; then
    PROVISIONER="csi-unity.dellemc.com"
  fi
fi

# Check volumeHandle for the requested provider
if [[ $PROVISIONER =~ powermax ]]; then
  check_powermax_volumehandle
elif [[ $PROVISIONER =~ powerstore ]]; then
  check_powerstore_volumehandle
elif [[ $PROVISIONER =~ isilon ]]; then
  check_isilon_volumehandle
elif [[ $PROVISIONER =~ vxflexos ]]; then
  check_vxflexos_volumehandle
elif [[ $PROVISIONER =~ unity ]]; then
  check_unity_volumehandle
else
  echo -e "\e[31m\"$PROVISIONER\" is unknown Provisionner\e[0m"
  usage
  exit
fi

if [[ -z $PVNAME ]]; then
  echo -e "\e[31mPVNAME is mandatory\e[0m"
  usage
  exit 1
else
  check_pvname
fi

if [[ $ACCESSMODE =~ ^ReadWriteOnce$\|^ReadOnlyMany$\|^ReadWriteMany$ ]]; then
  echo -e "\e[31m$ACCESSMODE is unknown Access Mode\e[0m"
  usage
  exit 1
fi

# Map volumeMode and filesystem type
VOLMODE=Filesystem
if [[ $FSTYPE =~ ^raw$ ]]; then
  VOLMODE=raw
  unset FSTYPE
elif [[ $FSTYPE =~ ^ext4$|^xfs$ ]]; then
  FSTYPE="fsType: $FSTYPE"
else
  echo -e "\e[31m\"$FSTYPE\" is unknown Filesystem type it should be raw or ext4 or xfs\e[0m"
  usage
  exit 1
fi

if ! [[ $SIZE =~ [0-9]+ ]]; then
  echo -e "\e[31mThe PV size: \"$SIZE\" must be an integer in Gi\e[0m"
  exit 1
fi


TMPPV=$(mktemp --suffix _static_pv.yaml)

##########
#Prepare PV
#########
cat <<EOF > "$TMPPV"
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PVNAME
spec:
  capacity:
    storage: ${SIZE}Gi
  accessModes:
    - $ACCESSMODE
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGECLASS
  volumeMode: $VOLMODE
  csi:
    driver: $PROVISIONER
    volumeHandle: $VOLUMEHANDLE
    $FSTYPE
EOF

##########
#Prepare PVC
#########
if ! [[ -z $PVCNAME ]]; then
cat <<EOF >> "$TMPPV"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVCNAME
  namespace: $NAMESPACE
spec:
  volumeName: $PVNAME
  storageClassName: $STORAGECLASS
  accessModes:
  - $ACCESSMODE
  resources:
    requests:
      storage: ${SIZE}Gi
EOF
fi


#########
#Ingest
##########
if [[ $DRYRUN == "false" ]]; then
  kubectl create -f "$TMPPV"
else
  cat "$TMPPV"
fi

rm "$TMPPV"
