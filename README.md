# Aspect Workflows images

Collection of packer scripts to create AMIs and GCP images for use with Aspect Workflows.

See https://docs.aspect.build/v/workflows/install/packer for accompanying Aspect Workflows documentation.

## Variants

### minimal

These include the minimal dependencies required by Workflows. Not all dependencies are listed in all Packer files, as some distributions base images have these dependencies already installed.

### docker

This adds docker on top of the minimal Workflows dependencies.

## AWS AMIs

AWS AMI packer files are found under the `/aws` directory.

To build AMS AMI's, first run `packer init`. This is only required once.

```
bazel run //:packer -- init aws/<distro>/<variant>.pkr.hcl"
```

Then run `packer build` passing the desired `version` and `region` as arguments.

```
bazel run //:packer -- build -var "version=<version>" -var "region=<region> aws/<distro>/<variant>.pkr.hcl"
```

You may also need to pass arguments `-var "vpc_id=<vpc_id>"` and `-var "subnet_id=<subnet_id>"` arguments if there is no default vpc in the region.

Pass `-var "encrypt_boot=true"` if you would like to build the AMI with an encrypted boot drive.

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "region=us-west-2" aws/amazon-linux-2/minimal.pkr.hcl`

## GCP images

To build GCP images, first run `packer init`. This is only required once.

```
bazel run //:packer -- init gcp/<distro>/<variant>.pkr.hcl"
```

Then run `packer build`, passing the desired `version`, `project` & `zone` as arguments:

```
bazel run //:packer -- build -var "version=<version>" -var "project=<project-name> -var "zone=<zone>" gcp/<distro>/<variant>.pkr.hcl
```

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "project=my-project" -var "zone=us-east5-a" gcp/debian-11/minimal.pkr.hcl`
