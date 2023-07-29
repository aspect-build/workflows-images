# Aspect Workflows images

Collection of packer scripts to create AMIs and GCP images for use with Aspect Workflows.

See https://docs.aspect.build/v/workflows/install/packer for accompanying Aspect Workflows documentation.

## Variants

### minimal

These include the minimal Workflows deps of `fuse` & `rsync`.

### docker

This adds docker on top of the minimal Workflows deps.

## AWS AMIs

AWS AMI packer files are found under the `/aws` directory.

To build AMS AMI's, pass the version and region as arguments:

```
bazel run //:packer -- build -var "version=<version>" -var "region=<region> aws/<distro>/<variant>.pkr.hcl"
```

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "region=us-west-2" aws/amazon-linux2/minimal.pkr.hcl`

## GCP images

To build GCP images, pass the version, project & zone as arguments:

```
bazel run //:packer -- build -var "version=<version>" -var "project=<project-name> -var "zone=<zone>" gcp/<distro>/<variant>.pkr.hcl
```

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "project=my-project" -var "zone=us-east5-a" gcp/debian/minimal.pkr.hcl`
