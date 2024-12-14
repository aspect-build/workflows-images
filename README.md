# Aspect Workflows Starter Images

Collection of packer scripts to create machine images for use with Aspect Workflows used to build Aspect Workflows starter images for AWS and GCP.

> [!TIP]
> These open source packer scripts may also be used as references for building custom machine images for Aspect Workflows.

## Variants

### minimal

These include the minimal dependencies required by Workflows. Not all dependencies are listed in all Packer files, as some distributions base images have these dependencies already installed.

### gcc

This adds gcc on top of the minimal Workflows dependencies.

### docker

This adds docker on top of the minimal Workflows dependencies.

### kitchen-sink

This adds docker, gcc and other deps such as `make` on top of the minimal Workflows dependencies.

## AWS AMIs

AWS AMI packer files are found under the `/aws` directory.

To build AMS AMI's, first run `packer init`. This is only required once.

```
packer init aws/<distro>/<variant>.pkr.hcl"
```

Then run `packer build` passing the desired `version` and `region` as arguments.

```
packer build -var "version=<version>" -var "region=<region> aws/<distro>/<variant>.pkr.hcl"
```

You may also need to pass arguments `-var "vpc_id=<vpc_id>"` and `-var "subnet_id=<subnet_id>"` arguments if there is no default vpc in the region.

Pass `-var "encrypt_boot=true"` if you would like to build the AMI with an encrypted boot drive.

By default we create amd64 (aka x86_64) AMI's but arm64 images can be created by specifying the argument `-var "arch=arm64"`

For example,

```
packer build -var "version=20241014-0" -var "region=us-west-2" aws/al2/minimal.pkr.hcl
```

## GCP images

To build GCP images, first run `packer init`. This is only required once.

```
packer init gcp/<distro>/<variant>.pkr.hcl"
```

Then run `packer build`, passing the desired `version`, `project` & `zone` as arguments:

```
packer build -var "version=<version>" -var "project=<project-name> -var "zone=<zone>" gcp/<distro>/<variant>.pkr.hcl
```

By default we create amd64 (aka x86_64) images but arm64 images can be created by specifying the argument `-var "arch=arm64"`

For example,

```
packer build -var "version=20241014-0" -var "project=my-project" -var "zone=us-east5-a" gcp/debian-11/minimal.pkr.hcl`
```
