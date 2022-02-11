//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Module.sol";

import "hardhat/console.sol";


interface IPolly {

  struct ModuleBase {
    string name;
    uint version;
    address implementation;
  }

  struct ModuleInstance {
    string name;
    uint version;
    address location;
  }

  struct Config {
    string name;
    address owner;
    ModuleInstance[] modules;
  }

}


contract Polly is Ownable {


    /// PROPERTIES ///

    mapping(string => mapping(uint => address)) private _modules;
    mapping(string => uint) private _module_versions;

    uint private _config_id;
    mapping(uint => IPolly.Config) private _configs;
    mapping(address => uint[]) private _configs_for_owner;

    //////////////////




    /// EVENTS ///

    event moduleUpdated(
      IPolly.ModuleBase indexed module
    );

    //////////////


    modifier onlyConfigOwner(uint config_id_) {
      require(isConfigOwner(config_id_, msg.sender), 'NOT_CONFIG_OWNER');
      _;
    }


    /// MODULES ///


    function updateModule(string memory name_, address implementation_) public onlyOwner {

      uint version_ = _module_versions[name_]+1;

      IPolly.ModuleBase memory module_ = IPolly.ModuleBase(
        name_, version_, implementation_
      );

      _modules[module_.name][module_.version] = module_.implementation;
      _module_versions[module_.name] = module_.version;

      emit moduleUpdated(module_);

    }



    function getModule(string memory name_, uint version_) public view returns(IPolly.ModuleBase memory){

      if(version_ < 1)
        version_ = _module_versions[name_];

      return IPolly.ModuleBase(name_, version_, _modules[name_][version_]);

    }


    function moduleExists(string memory name_, uint version_) public view returns(bool exists_){
      if(_modules[name_][version_] != address(0))
        exists_ = true;
      return exists_;
    }



    /// CONFIGS

    function _cloneAndAttachModule(uint config_id_, string memory name_, uint version_) private {
      console.log(string(abi.encodePacked('CLONING -> ', name_)));
      address implementation_ = _modules[name_][version_];

      IModule module_ = IModule(Clones.clone(implementation_));
      module_.init(msg.sender);

      _attachModule(config_id_, name_, version_, address(module_));

    }

    function _attachModule(uint config_id_, string memory name_, uint version_, address location_) private {
      console.log(string(abi.encodePacked('ATTACHING -> ', name_)));
      _configs[config_id_].modules.push(IPolly.ModuleInstance(name_, version_, location_));
    }


    function useModule(uint config_id_, IPolly.ModuleInstance memory mod_) public onlyConfigOwner(config_id_) {

      require(isConfigOwner(config_id_, msg.sender), 'NOT_CONFIG_OWNER');

      if(!moduleExists(mod_.name, mod_.version))
        return;

      IPolly.ModuleBase memory base_ = getModule(mod_.name, mod_.version);
      IModule.ModuleInfo memory base_info_ = IModule(_modules[mod_.name][mod_.version]).getModuleInfo();

      // Location is 0 - proceed to attach or clone
      if(mod_.location == address(0x00)){
        if(base_info_.clone)
          _cloneAndAttachModule(config_id_, base_.name, base_.version);
        else
          _attachModule(config_id_, base_.name, base_.version, base_.implementation);
      }
      else {
        // Reuse - attach module
        _attachModule(config_id_, mod_.name, mod_.version, mod_.location);
      }

      _configs[config_id_].modules.push();

    }

    function useModules(uint config_id_, IPolly.ModuleInstance[] memory mod_) public onlyConfigOwner(config_id_) {
      for(uint256 i = 0; i < mod_.length; i++) {
        useModule(config_id_, mod_[i]);
      }
    }

    function createConfig(string memory name_, IPolly.ModuleInstance[] memory mod_) public {

      _config_id++;
      _configs[_config_id].name = name_;
      _configs[_config_id].owner = msg.sender;
      _configs_for_owner[msg.sender].push(_config_id);
      useModules(_config_id, mod_);

    }

    function getConfigsForOwner(address owner_) public view returns(uint[] memory){
      return _configs_for_owner[owner_];
    }

    function getConfig(uint config_id_) public view returns(IPolly.Config memory){
      return _configs[config_id_];
    }

    function isConfigOwner(uint config_id_, address check_) public view returns(bool){
      IPolly.Config memory config_ = getConfig(config_id_);
      return (config_.owner == check_);
    }

    function transferConfig(uint config_id_, address to_) public {
      require(isConfigOwner(config_id_, msg.sender), "NOT_CONFIG_OWNER");
      _configs[config_id_].owner = to_;
    }


}
