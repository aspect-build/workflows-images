# Aspect Workflows images

Collection of packer scripts to create AMIs and GCP images for use with Aspect Workflows.

See https://docs.aspect.build/v/workflows/install/packer for accompanying Aspect Workflows documentation.

## AWS AMIs

```
bazel run //:packer -- build -var "version=<version>" -var "region=<region> aws/amazon-linux2/minimal.pkr.hcl"
bazel run //:packer -- build -var "version=<version>" -var "region=<region> aws/buildkite-amazon-linux2/minimal.pkr.hcl"
bazel run //:packer -- build -var "version=<version>" -var "region=<region> aws/debian/minimal.pkr.hcl"
```

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "region=us-west-2" aws/amazon-linux2/minimal.pkr.hcl`

## GCP images

```
bazel run //:packer -- build -var "version=<version>" -var "project=<project-name> -var "zone=<zone>" gcp/debian/minimal.pkr.hcl
bazel run //:packer -- build -var "version=<version>" -var "project=<project-name> -var "zone=<zone>" gcp/ubuntu/minimal.pkr.hcl
```

For example,

`bazel run //:packer -- build -var "version=1-0-0" -var "project=my-project" -var "zone=us-east5-a" gcp/debian/minimal.pkr.hcl`
