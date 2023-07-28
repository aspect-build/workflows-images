load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def packer():
    version = "1.8.3"
    build_file_content = """exports_files(["packer"])"""

    http_archive(
        name = "packer_macos_aarch64",
        build_file_content = build_file_content,
        sha256 = "5cc53abbc345fc5f714c8ebe46fd79d5f503f29375981bee6c77f89e5ced92d3",
        urls = ["https://releases.hashicorp.com/packer/{0}/packer_{0}_darwin_arm64.zip".format(version)],
    )
    http_archive(
        name = "packer_macos_x86_64",
        build_file_content = build_file_content,
        sha256 = "ef1ceaaafcdada65bdbb45793ad6eedbc7c368d415864776b9d3fa26fb30b896",
        urls = ["https://releases.hashicorp.com/packer/{0}/packer_{0}_darwin_amd64.zip".format(version)],
    )
    http_archive(
        name = "packer_linux_x86_64",
        build_file_content = build_file_content,
        sha256 = "0587f7815ed79589cd9c2b754c82115731c8d0b8fd3b746fe40055d969facba5",
        urls = ["https://releases.hashicorp.com/packer/{0}/packer_{0}_linux_amd64.zip".format(version)],
    )
