# Contributing to this repository

## Adding dependencies

### Amazon Linux 2 yum dependencies

If you have a working docker setup, you can query the packages like so:

```
docker run --rm -it --entrypoint bash amazonlinux:2
> bash-4.2# yum search <package>
```
