// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {ENS} from "../ens/ENS.sol";
import {ENSRegistry} from "../ens/ENSRegistry.sol";
import {IResolver} from "../ens/interfaces/IResolver.sol";
import {IBaseRegistrar} from "../ens/interfaces/IBaseRegistrar.sol";
import {BaseRegistrarImplementation} from "../ens/BaseRegistrarImplementation.sol";
import {SubdomainRegistrar} from "../SubdomainRegistrar.sol";
import {BaseTest, console} from "./base/BaseTest.sol";
import {Namehash} from "./utils/namehash.sol";
import {TestResolver} from "./utils/TestResolver.sol";
import {TestErc721Token} from "./utils/TestErc721Token.sol";
import "forge-std/Vm.sol";

contract ContractTest is BaseTest {

    address controller = address(0x1337c);
    address bob = address(0x133702);
    address alice = address(0x133706969);
    bytes32 namehashEth = Namehash.namehash('eth');

    ENS ens;
    IBaseRegistrar registrar;
    SubdomainRegistrar subdomainRegistrar;
    IResolver resolver;
    TestErc721Token token;

    function setUp() public {
        vm.label(controller, "Controller");
        vm.label(bob, "Bob");
        vm.label(alice, "Alice");
        vm.label(address(this), "TestContract");

        ens = new ENSRegistry();
        registrar = new BaseRegistrarImplementation(ens, namehashEth);

        // Bootstrap ENS.
        registrar.addController(controller);
        ens.setSubnodeOwner(
            bytes32(0),
            keccak256(abi.encodePacked('eth')),
            address(registrar)
        );
        vm.warp(90 days + 1); // Warp ahead of the ENS grace period.
        
        // set up subdomain registrar contract 
        resolver = new TestResolver();

        // unclear why this token is actually necessary, leave it for now
        token = new TestErc721Token();
        subdomainRegistrar = new SubdomainRegistrar(ens, token, resolver);
    }

    function testValidateSetUp() public {
        assertEq(Namehash.namehash('eth'), 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae);
        assertEq(ens.owner(namehashEth), address(registrar));
    }

    function testRegisterNounsDomain() public {
        uint256 hashedNouns = uint256(keccak256(abi.encodePacked('nouns')));
        registerTLD(hashedNouns);
        assertEq(ens.owner(Namehash.namehash('nouns.eth')), bob);
        assertEq(registrar.ownerOf(hashedNouns), bob);
    }
    
    function testRegisterSubdomain() public {
        uint256 tldLabel = uint256(keccak256(abi.encodePacked('nouns')));
        registerTLD(tldLabel);

        vm.startPrank(bob);
        // must be the owner of the token to register 
        registrar.approve(address(subdomainRegistrar), tldLabel);
        subdomainRegistrar.configureDomain('nouns');
        vm.stopPrank();

        vm.startPrank(alice);
        token.mint(alice, 111);
        token.mint(alice, 101);
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), 'alice', alice);
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), '111', alice);
        vm.expectRevert("ERC721: owner query for nonexistent token");
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), '2111', alice);

        vm.stopPrank();

        vm.startPrank(bob);
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), 'bob', bob);
        vm.expectRevert(); // should not be able to register another users token id 
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), '101', bob);
        vm.expectRevert("ERC721: owner query for nonexistent token");
        subdomainRegistrar.register(keccak256(abi.encodePacked('nouns')), '2', bob);
        vm.stopPrank();

        assertEq(ens.owner(Namehash.namehash('alice.nouns.eth')), address(subdomainRegistrar));
        assertEq(resolver.addr(Namehash.namehash('alice.nouns.eth')), alice);
        assertEq(ens.owner(Namehash.namehash('111.nouns.eth')), address(subdomainRegistrar));
        assertEq(resolver.addr(Namehash.namehash('111.nouns.eth')), alice);
        assertEq(resolver.addr(Namehash.namehash('2111.nouns.eth')), address(0));
        assertEq(ens.owner(Namehash.namehash('bob.nouns.eth')), address(subdomainRegistrar));
        assertEq(resolver.addr(Namehash.namehash('bob.nouns.eth')), bob);
    }
    
    function registerTLD(uint256 hashedTLD) private {
        vm.startPrank(controller);
        registrar.register(
            hashedTLD,
            bob,
            1 days
        );
        vm.stopPrank();
    }
}
