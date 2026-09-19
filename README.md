# Aspect Workflows Starter Images

Packer scripts that build the machine images Aspect publishes for Aspect Workflows CI
runners on AWS and GCP.

> [!TIP]
> These open source packer scripts may also be used as references for building custom machine images for Aspect Workflows.

**Looking for a published image to use?**
[Starter machine images](https://aspect.build/docs/aspect-workflows/shapes/self-hosted/infrastructure/starter-images)
in the Aspect docs is the reference: the current version, what each variant contains, the
naming scheme, and how to find an image in your region or project. This README covers
building the images, not consuming them.

## Variants

`minimal`, `gcc`, `docker` and `kitchen-sink` — see
[the docs](https://aspect.build/docs/aspect-workflows/shapes/self-hosted/infrastructure/starter-images#variants)
for what each one installs.

## Build an AWS AMI

AWS AMI packer files are found under the `/aws` directory.

To build AWS AMIs, first run `packer init`. This is only required once.

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

## Build a GCP image

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
packer build -var "version=20241014-0" -var "project=my-project" -var "zone=us-east5-a" gcp/debian-12/minimal.pkr.hcl`
```
