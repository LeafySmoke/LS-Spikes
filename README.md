# LS-Spikes

> A realistic FiveM resource for deploying stop sticks with durability, deflation mechanics, and interactive deployment features.

## 🎯 Overview

**LS-Spikes** is a comprehensive FiveM resource designed to add realistic stop stick deployment functionality to your GTA V roleplay server. The resource features advanced durability systems, vehicle deflation mechanics, and intuitive player interactions using modern frameworks.

### Features

- 🎪 **Realistic Stop Stick Deployment** - Deploy stop sticks with physics-based interactions
- 🔧 **Durability System** - Stop sticks degrade with vehicle damage and eventually break
- 🚗 **Vehicle Deflation Mechanics** - Vehicles lose control when hitting deployed stop sticks
- 🖱️ **Interactive Targeting** - Easy deployment using ox_target for seamless UX
- ⚙️ **Highly Configurable** - Extensive configuration options for customization
- 📊 **Server Synchronization** - Reliable server-side state management
- 🎨 **Modern Framework Integration** - Built with ox_lib and ox_target dependencies

## 📋 Requirements

This resource requires the following dependencies:

- **[ox_lib](https://github.com/overextended/ox_lib)** - Core library for utilities and UI components
- **[ox_target](https://github.com/overextended/ox_target)** - Interactive targeting system for stop stick deployment

## 🚀 Installation

### Step 1: Download Dependencies

Ensure you have the required frameworks installed in your resources folder:

```bash
# In your resources directory
git clone https://github.com/overextended/ox_lib.git
git clone https://github.com/overextended/ox_target.git
```

### Step 2: Install LS-Spikes

Download and extract LS-Spikes into your resources folder:

```bash
git clone https://github.com/LeafySmoke/LS-Spikes.git
```

### Step 3: Configure server.cfg

Add the following to your `server.cfg`:

```cfg
ensure ox_lib
ensure ox_target
ensure LS-Spikes
```

### Step 4: Customize Configuration

Edit `shared/config.lua` to adjust settings for your server's needs (see Configuration section below).

## ⚙️ Configuration

The `shared/config.lua` file contains all configurable options for the resource:

```lua
Config = {}

-- Stop stick deployment settings
Config.DeploymentDistance = 5.0        -- Distance in front of player where stop stick deploys
Config.DeploymentAnimation = "combat@damage@rb_writhe"  -- Animation used during deployment
Config.DeploymentTime = 2000           -- Deployment animation duration (ms)

-- Durability settings
Config.MaxDurability = 100             -- Maximum durability points
Config.DamagePerHit = 25               -- Durability loss per vehicle collision
Config.DurabilityRegenRate = 0.1       -- Durability regeneration per tick

-- Vehicle deflation settings
Config.DeflationDamage = 10            -- Tire damage per collision
Config.SpeedReduction = 0.7            -- Speed multiplier after hitting spike strip
Config.ControlLoss = 0.3               -- Control loss intensity (0-1)

-- Server settings
Config.SyncInterval = 100              -- Server sync interval (ms)
Config.MaxConcurrentSpikes = 50        -- Max spikes allowed at once
```

## 📁 Project Structure

```
LS-Spikes/
├── client/
│   └── main.lua              # Client-side logic for stop stick deployment and interactions
├── server/
│   └── main.lua              # Server-side logic for durability, synchronization, and events
├── shared/
│   └── config.lua            # Configuration file for all customizable settings
├── INSTALL/                  # Installation documentation
├── fxmanifest.lua            # Resource manifest with dependencies and script loading
└── .gitattributes            # Git attributes for proper line endings
```

### File Descriptions

- **client/main.lua** (63KB) - Handles client-side rendering, animations, and user interactions for deploying stop sticks
- **server/main.lua** (15KB) - Manages server-side state, durability tracking, vehicle deflation logic, and client synchronization
- **shared/config.lua** (6.7KB) - Centralized configuration with all adjustable parameters for gameplay mechanics

## 🎮 Usage

### Deploying Stop Sticks

1. Aim at a vehicle using ox_target
2. Select "Deploy Stop Stick" from the targeting menu
3. Watch as your character deploys the stop stick in front of the vehicle
4. The stop stick will remain until it's destroyed by vehicle impacts

### Mechanics in Action

**Before Collision:**
- Stop stick is deployed on the ground
- Vehicles can see the visual indicator

**During Collision:**
- Vehicle loses control temporarily
- Tires take damage
- Stop stick durability decreases

**After Durability Depleted:**
- Stop stick disappears
- New stop sticks can be deployed

## 🔧 Developer Documentation

### Client-Side Events

The client emits events that the server listens for:

```lua
TriggerServerEvent('ls-spikes:deploy', {
    position = vector3(x, y, z),
    heading = heading,
    playerId = GetPlayerServerId(PlayerId())
})
```

### Server-Side Events

Server events that clients can listen to:

```lua
TriggerClientEvent('ls-spikes:sync', -1, spikeData)
TriggerClientEvent('ls-spikes:remove', -1, spikeId)
```

### Exports

Useful exports for scripting integrations:

```lua
-- Get all active spike strips
local spikes = exports['LS-Spikes']:GetActiveSpikes()

-- Get spike durability
local durability = exports['LS-Spikes']:GetSpikeDurability(spikeId)

-- Remove a spike manually
exports['LS-Spikes']:RemoveSpike(spikeId)
```

## 🐛 Troubleshooting

### Stop Sticks Not Showing
- Verify ox_lib and ox_target are properly installed and started
- Check that `LS-Spikes` is listed after the dependencies in `server.cfg`
- Restart the resource with `/restart LS-Spikes`

### Durability Not Decreasing
- Ensure vehicles are actually colliding with the stop sticks
- Check collision settings in `shared/config.lua`
- Review server console for error messages

### Targeting Menu Not Appearing
- Verify ox_target is running: `/status` in console
- Check that players have the correct permissions
- Restart ox_target with `/restart ox_target`

### Performance Issues
- Reduce `Config.MaxConcurrentSpikes` if experiencing lag
- Increase `Config.SyncInterval` for less frequent syncing
- Disable unnecessary debug options

## 📝 License

This project is open-source and available for use in your FiveM server. Please credit LeafySmoke if you use this resource.

## 🤝 Support & Contributions

- **Bug Reports**: Open an issue on GitHub
- **Feature Requests**: Discuss in GitHub Discussions
- **Contributions**: Pull requests are welcome!

## 📚 Resources & Links

- [FiveM Documentation](https://docs.fivem.net/)
- [ox_lib GitHub](https://github.com/overextended/ox_lib)
- [ox_target GitHub](https://github.com/overextended/ox_target)
- [FiveM Community](https://forum.cfx.re/)

---

**Version:** 1.0.0  
**Last Updated:** 2026-04-02 03:26:19  
**Author:** LeafySmoke  
**Maintained:** Active