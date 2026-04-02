fx_version "cerulean"
game "gta5"

author "LeafySmoke"
description "Realistic Stop Stick Deployment with Durability and Deflation Mechanics"
version "1.0.0"

dependency "ox_lib"
dependency "ox_target"

shared_scripts {
    "@ox_lib/init.lua",
    "shared/config.lua"
}

client_scripts {
    "client/main.lua"
}

server_scripts {
    "server/main.lua"
}
dependency '/assetpacks'