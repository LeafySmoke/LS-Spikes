fx_version "cerulean"
game "gta5"

author "SwisserAI"
description "Realistic Stop Stick Deployment - Generated with SwisserAI - https://ai.swisser.dev"
version "1.0.0"

dependency "ox_lib"
dependency "ox_target"

shared_script "shared/config.lua"

client_scripts {
    "client/main.lua"
}

server_scripts {
    "server/main.lua"
}