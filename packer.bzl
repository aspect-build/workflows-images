"""Wrapper around a packer sh_binary target"""

def packer(name, **kwargs):
    native.sh_binary(
        name = name,
        srcs = ["packer.sh"],
        args = ["$(rootpath //:packer_binary)"],
        data = ["//:packer_binary"] + kwargs.pop("data", []),
        tags = ["manual"] + kwargs.pop("tags", []),
        visibility = kwargs.pop("visibility", ["//:__subpackages__"]),
        **kwargs
    )
