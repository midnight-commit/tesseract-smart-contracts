## Teleporter Messenger Contract and Example Cross Chain Applications
This directory contains Solidity contracts implementing the Teleporter messaging protocol and example cross-chain applications built using Teleporter.

This directory is set up as a [Foundry](https://github.com/foundry-rs/foundry) project. Follow the linked guide to install the necessary dependencies. Further documentation about given contracts can be found in `src/Teleporter/` and `src/CrossChainApplications`.

## Building and Running
- To compile the contracts run `forge build` from this directory.
- Similarly, to run unit tests, run `forge test`.
- See additional testing and deployment options [here](https://book.getfoundry.sh/forge/).

## Generate documentation
- Documentation can be generated by running `forge doc --build` from this repository. By default, this will generate documentation to `contracts/docs/`, and an HTML book to `contracts/docs/book/`. It's also possible to serve this book locally by running `forge doc --serve <PORT>`.