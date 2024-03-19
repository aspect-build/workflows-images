TAGS = {
    "workflows-images:ubuntu-2004-minimal": "aws/ubuntu-2004/minimal.pkr.hcl"
}

# bazel run //:packer -- build -var "version=jesse-test" -var "arch=arm64" -var "region=us-east-2" -only "docker.ubuntu" "aws/ubuntu-2004/minimal.pkr.hcl"

# docker save -o image.tar sha256:3b1df0fbd99beb4bfb31d65d40c1329b322e057a3080f257b10f15a1dfa4bae5

def pretty_name(tag):
    return tag.replace(":", "_").replace("-", "_")

def docker_images():
    for tag in TAGS:

        # TODO: Pipe these logs into a file and make that another output?
        cmds = [
            "$(location //:packer_binary) init %s" % TAGS[tag],
            " ".join([
                # https://developer.hashicorp.com/packer/docs/configure#packer_config_dir
                "PACKER_CONFIG_DIR=$$(pwd)/config",
                "$(location //:packer_binary)",
                "build",
                "-var \"version=jesse-test\"",
                "-var \"arch=arm64\"",
                "-var \"region=us-east-2\"",
                "-only \"docker.ubuntu\"",
                "\"%s\"" % TAGS[tag]
            ]),
            "docker save -o $@ %s" % tag,
        ]
        native.genrule(
            name = pretty_name(tag),
            srcs = [
                "//:%s" % TAGS[tag]
            ],
            outs = [
                "%s.tar" % pretty_name(tag)
            ],
            cmd = " && ".join(cmds),
            tools = [
                "//:packer_binary"
            ],
            tags = [
                "requires-network"
            ]
        )