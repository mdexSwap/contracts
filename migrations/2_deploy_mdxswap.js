const MdxToken = artifacts.require("MdxToken");
const CoinChef = artifacts.require("CoinChef");
const MdxConfig = require('../config/config');

module.exports = function (deployer) {
    deployer.deploy(MdxToken).then(function() {
        return deployer.deploy(
            CoinChef,
            MdxToken.address, 
            MdxConfig.mdxswap.dev_address, 
            MdxConfig.mdxswap.mdx_perblock,
            MdxConfig.mdxswap.start_block
        );
    });
};