# Package

version = "0.0.1"
author = "Promethei core contributors"
description = "Crawler for Promethei networks"
license = "MIT"
skipDirs = @["tests"]
bin = @["prometheicrawler"]
binDir = "build"

# Dependencies
requires "nim >= 2.0.14 & < 3.0.0"
requires "secp256k1 >= 0.6.0 & < 0.7.0"
requires "protobuf_serialization >= 0.3.0 & < 0.4.0"
requires "nimcrypto >= 0.6.2 & < 0.7.0"
requires "bearssl >= 0.2.5 & < 0.3.0"
requires "chronicles >= 0.10.2 & < 0.11.0"
requires "chronos >= 4.0.3 & < 4.1.0"
# requires "libp2p >= 1.5.0 & < 2.0.0"
requires "libp2p#036e110a6080fba1a1662c58cfd8c21f9a548021"
  # Same as promethei-0.2.0 uses.
requires "https://github.com/promethei-storage/nim-poseidon2#4e2c6e619b2f2859aaa4b2aed2f346ea4d0c67a3"

requires "metrics >= 0.1.0 & < 0.2.0"
requires "stew >= 0.2.0 & < 0.3.0"
requires "stint >= 0.8.1 & < 0.9.0"
requires "https://github.com/promethei-storage/nim-datastore >= 0.2.0 & < 0.3.0"
requires "questionable >= 0.10.15 & < 0.11.0"
requires "https://github.com/promethei-storage/nim-nim-promethei-dht#89b281fc8d84097d4cd1f8a53fac68bd23433f59"
requires "docopt >= 0.7.1 & < 1.0.0"
requires "nph >= 0.6.1 & < 1.0.0"
requires "ethers >= 1.0.0 & < 2.0.0"

task format, "Formatting...":
  exec "nph ./"

task test, "Run tests":
  exec "nimble install -d -y"
  withDir "tests":
    exec "nimble test"
