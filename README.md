# Stabull Staking

## Table of Contents

- [Project Description](#project-description)
- [Technologies Used](#technologies-used)
- [Folder Structure](#folder-structure)
- [Install and Run](#install-and-run)
- [Testing](#testing)
- [Deploy & Verify](#deploy--verify)
- [Gas Report](#gas-report)
- [Contract Size](#contract-size)
- [Documentation](#documentation)

## Project Description

Stabull Staking is a decentralized finance (DeFi) protocol designed to provide users with a seamless experience for staking tokens. It includes advanced features such as reward distribution, governance control, and fee management. The protocol ensures secure and transparent staking while minimizing counterparty risk.

By using Stabull Staking, users can easily stake their tokens, earn rewards in the form of staking yields. The protocol employs state-of-the-art smart contract technology to ensure security, efficiency, and transparency.

## Technologies Used

- Solidity
- Foundry



## Folder Structure

A typical top-level directory layout:

├── lib # required files (foundry packages)

├── docs # Documentation files (alternatively doc)

├── src # Source files (alternatively lib or app)

├── test # Automated tests (alternatively spec or tests)

├── LICENSE

└── README.md



## Install and Run

To install and run the project, follow these steps:

1. Run `forge compile` to compile all contracts.


## Testing

To test the files, execute the following steps:

1. Run `forge test` to run the Foundry test cases.
2. Run `forge coverage` to get the coverage of test cases.

## Deploy & Verify

To deploy and verify the contracts, execute the following steps:

1. Run `forge create --rpc-url <rpc-url> --private-key <private-key> --etherscan-api-key <api-key> --constructor-args <constructor-args> --verify src/StakingFactory.sol:StakingFactory` to deploy the StakingFactory contract.
2. Run `forge verify --network <network> <contract-address> <constructor-args>` to verify the contract on Etherscan.

Similarly done for the StakingPool contract.

## Gas Report

To generate the gas report of test cases:

1. Run `forge test --gas-report` to generate the gas report.

## Contract Size

To generate the contract sizes:

1. Run `forge build --sizes` to generate the contract sizes.

## Documentation

- [Contracts overview](./docs/ContractGuide.md)
- [Gas report](./docs/gas-report.png)
- [Contract sizes](./docs/ContractSize.png)
- [Test coverage](./docs/TestCoverage.png)
