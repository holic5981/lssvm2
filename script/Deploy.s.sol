// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LSSVMPair} from "../src/LSSVMPair.sol";
import {LSSVMRouter} from "../src/LSSVMRouter.sol";
import {LSSVMRouter2} from "../src/LSSVMRouter2.sol";
import {LSSVMPairETH} from "../src/LSSVMPairETH.sol";
import {CREATE3Script} from "./base/CREATE3Script.sol";
import {LSSVMPairERC20} from "../src/LSSVMPairERC20.sol";
import {XykCurve} from "../src/bonding-curves/XykCurve.sol";
import {LSSVMPairFactory} from "../src/LSSVMPairFactory.sol";
import {LinearCurve} from "../src/bonding-curves/LinearCurve.sol";
import {ExponentialCurve} from "../src/bonding-curves/ExponentialCurve.sol";

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run()
        external
        returns (
            LSSVMPairFactory factory,
            LSSVMRouter router,
            LSSVMRouter2 router2,
            LinearCurve linearCurve,
            ExponentialCurve exponentialCurve,
            XykCurve xykCurve
        )
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        uint256 protocolFee = vm.envUint("PROTOCOL_FEE");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address royaltyRegistry = vm.envAddress("ROYALTY_REGISTRY");

        vm.startBroadcast(deployerPrivateKey);

        // deploy factory
        {
            LSSVMPairETH ethTemplate = LSSVMPairETH(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairETH"),
                        bytes.concat(type(LSSVMPairETH).creationCode, abi.encode(royaltyRegistry))
                    )
                )
            );
            LSSVMPairERC20 erc20Template = LSSVMPairERC20(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMPairERC20"),
                    bytes.concat(type(LSSVMPairERC20).creationCode, abi.encode(royaltyRegistry))
                )
            );
            address deployer = vm.addr(deployerPrivateKey);
            factory = LSSVMPairFactory(
                payable(
                    create3.deploy(
                        getCreate3ContractSalt("LSSVMPairFactory"),
                        bytes.concat(
                            type(LSSVMPairFactory).creationCode,
                            abi.encode(ethTemplate, erc20Template, protocolFeeRecipient, protocolFee, deployer)
                        )
                    )
                )
            );
        }

        // deploy bonding curves
        linearCurve = LinearCurve(create3.deploy(getCreate3ContractSalt("LinearCurve"), type(LinearCurve).creationCode));
        exponentialCurve = ExponentialCurve(
            create3.deploy(getCreate3ContractSalt("ExponentialCurve"), type(ExponentialCurve).creationCode)
        );
        xykCurve = XykCurve(create3.deploy(getCreate3ContractSalt("XykCurve"), type(XykCurve).creationCode));

        // whitelist bonding curves
        factory.setBondingCurveAllowed(linearCurve, true);
        factory.setBondingCurveAllowed(exponentialCurve, true);
        factory.setBondingCurveAllowed(xykCurve, true);

        // deploy routers
        router = LSSVMRouter(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMRouter"),
                    bytes.concat(type(LSSVMRouter).creationCode, abi.encode(factory))
                )
            )
        );
        router2 = LSSVMRouter2(
            payable(
                create3.deploy(
                    getCreate3ContractSalt("LSSVMRouter2"),
                    bytes.concat(type(LSSVMRouter2).creationCode, abi.encode(factory))
                )
            )
        );

        // whitelist routers
        factory.setRouterAllowed(router, true);
        factory.setRouterAllowed(LSSVMRouter(payable(address(router2))), true);

        // transfer factory ownership
        {
            address owner = vm.envAddress("OWNER");
            factory.transferOwnership(owner);
        }

        vm.stopBroadcast();
    }
}