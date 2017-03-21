-- Imports
local discordia = require('discordia')
local files = require('fs')
local timer = require('timer')

-- Discord interfaces
local client = discordia.Client()
local gameChannel = nil

-- Timer durations (in milliseconds)
local waitTime = 5 * 1000
local roleTime = 20 * 1000
local dayTime = 5 * 1000
local eveTime = 10 * 1000

-- Game state information
local gameState, players, playerRoles, votes, thread

function init()
    gameState = 'idle'
    players = {}
    playerRoles = {
        villager = {},
        werewolf = {},
        seer = {},
        robber = {},
        troublemaker = {},
    }
    votes = {}
end

function addPlayer(user)
    for idx, player in pairs(players) do -- make sure they're not already in
        local other = player
        if other.name == user.name and other.discriminator == user.discriminator then
            user:sendMessage('You have already been added to this game.')
            return
        end
    end

    table.insert(players, user)

    messagePlaza('Added player ' .. fullUserName(user) .. ' (total: ' .. #players .. ')')
end

function startGame()
    if #players < 3 then
        messagePlaza('There must be at least 3 people to start a game.')
        endGame()
    else
        client:setGameName('Werewolf')
        gameState = 'started'
        local rolePoolFull, rolePool = assignRoles()

        local rolesText = ""
        for role, number in pairs(rolePoolFull) do
            if number == 0 then
                -- don't add to the list
            elseif number == 1 then
                rolesText = rolesText .. number .. ' **' .. role .. '** role, '
            else
                rolesText = rolesText .. number .. ' **' .. role .. '** roles, '
            end 
        end
        rolesText = rolesText .. 'and a ' .. string.lower(getAdjective()) .. ' ' .. string.lower(getAnimal())

        messagePlaza('Game started with role card deck: ' .. rolesText .. '\n**It is now night time.**')

        if #playerRoles["werewolf"] == 1 then
            messageUser(playerRoles["werewolf"][1], "You are the only werewolf alive.")
        else
            for _, user in pairs(playerRoles["werewolf"]) do
                local werewolves = {}
                for _, v in ipairs(playerRoles["werewolf"]) do
                    table.insert(werewolves, fullUserName(v))
                end
                messageUser(user, "Werewolves: " .. table.concat(werewolves, ", ") .. "\nFeel free to start a (group) DM.")
            end
        end

        seer(rolePool)

        --endGame()
    end
end

function seer(rolePool)
    gameState = 'seer'

    messagePlaza("Seer, time to wake up.")
    local seer = playerRoles["seer"][1]
    if seer ~= nil then
        messageUser(seer, "Please DM me `!divine *nickname*` (with or without the 4-digit identifier) to spy on someone's role, or `!divine2` to view two unused role cards.")
    end

    coroutine.wrap(function()
        timer.sleep(roleTime)
        if seer ~= nil then
            if seer.target == nil then -- Seer views two roles
                local divinedRoles = {}
                -- Grab two unused roles
                for i=1,2 do
                    -- Grab all of the role names
                    local roles = {}
                    for k in pairs(rolePool) do
                        table.insert(roles, k)
                    end

                    -- Divine role
                    local role = roles[math.random(#roles)]
                    table.insert(divinedRoles, role)

                    rolePool[role] = rolePool[role] - 1

                    if rolePool[role] == 0 then
                        rolePool[role] = nil
                    end
                end

                -- Inform the seer
                messageUser(seer, "You divine two role cards that are not in play: **" .. table.concat(divinedRoles, "**, and **") .. "**")
            else -- Seer divines a player's role
                for role, users in pairs(playerRoles) do
                    for _, user in users do
                        if seer.target == user then
                            messageUser("You divine that " .. user.name .. " is a " .. role)
                        end
                    end
                end
            end
        end

        messagePlaza("The seer goes back to bed.")
        robber()
    end)()
end

function robber()
    gameState = 'robber'

    messagePlaza("Robber, time to wake up.")
    local robber = playerRoles["robber"][1]
    if robber ~= nil then
        messageUser(robber, "Please DM me `!rob *nickname*` (with or without the 4-digit identifier) to rob another user's role.")
    end

    coroutine.wrap(function()
        timer.sleep(roleTime)
        if robber ~= nil then
            if robber.target == nil then
                messageUser(robber, "You chose not to rob anybody tonight. Bold strategy, Cotton.")
            else
                local roleName
                -- Holy nesting, Batman.
                for role, rolePlayers in pairs(playerRoles) do
                    for i, player in ipairs(rolePlayers) do
                        if player == robber.target then
                            roleName = role
                            rolePlayers[i] = robber
                            break -- No goto supported until Lua v5.2 (LuaJIT currently supports up to v5.1)
                        end
                    end
                end
                playerRoles["robber"][1] = robber.target
                messageUser(robber, "You swapped identities with ".. robber.target.name .." in the dead of night. You are now a **".. roleName .."** on the **".. getTeam(roleName) .."** team.")
            end
        end

        messagePlaza("The robber goes back to bed.")
        troublemaker()
    end)()
end

function troublemaker()
    gameState = 'troublemaker'

    -- TODO
    --[[messagePlaza("Troublemaker, time to wake up.")
    local troublemaker = playerRoles["troublemaker"][1]
    if troublemaker ~= nil then
        messageUser(troublemaker, "Please DM me `!prank *nickname1* *nickname2*` (with or without the 4-digit identifier) to swap those players roles.")
    end]]--
    
    startDay()
end

function startDay()
    gameState = 'day'

    messagePlaza("It's the start of a new day! Who, if anyone, is a werewolf? You have ".. dayTime / 1000 .." seconds to discuss!")

    coroutine.wrap(function()
        timer.sleep(dayTime)
        startEve()
    end)()
end

function startEve()
    gameState = 'eve'

    messagePlaza("The sun is starting to set, leaving the bitter evening cold. It is time to decidie who to hang.\n"
    .. "To cast your vote, DM me either `!vote *nickname*` or `!novote`. You have ".. eveTime / 1000 .." seconds to decide.")

    coroutine.wrap(function()
        timer.sleep(eveTime)
        results()
    end)()
end

function results()
    local modeMap = {}
    local maxEl = {}
    local maxCount = 0

    for _, victim in pairs(votes) do
        if modeMap[victim] == nil then
            modeMap[victim] = 1
        else
            modeMap[victim] = modeMap[victim] + 1
        end

        if modeMap[victim] > maxCount then
            maxEl = {victim}
            maxCount = modeMap[victim]
        else
            table.insert(maxEl, victim)
            maxCount = modeMap[victim]
        end
    end

    local message = "The results are in! "
    if #maxEl == 0 then
        message = message .. "Absolutely **nobody** voted!\n"
    elseif #maxEl == 1 then
        message = message .."With ".. maxCount .." votes, the town decides to hang ".. maxEl[1].name .."!"
    else
        message = message .."There was a tie! Nobody was hanged!"
    end
    message = message .."\nGame over! Winners: " -- TODO

    messagePlaza(message)
    endGame()
end

function assignRoles()
    -- Base pool
    local rolePool = {
        villager = #players - 2,
        werewolf = 2,
        seer = 1,
        robber = 1,
        troublemaker = 1,
    }

    local rolePoolFull = {} -- to return
    for k, v in pairs(rolePool) do
        rolePoolFull[k] = v
    end

    -- Role selection is biased towards role diversity
    for _, user in pairs(players) do
        -- Grab all of the role names
        local roles = {}
        for k in pairs(rolePool) do
            table.insert(roles, k)
        end

        local role = roles[math.random(#roles)]
        table.insert(playerRoles[role], user)
        messageUser(user, 'You are a **'.. role ..'** on the **'.. getTeam(role) ..'** team.')

        rolePool[role] = rolePool[role] - 1
        if rolePool[role] == 0 then
            rolePool[role] = nil
        end
    end

    return rolePoolFull, rolePool
end

function getTeam(role)
    local villagers = {"seer", "robber", "troublemaker", "villager"}
    local werewolves = {"werewolf"}

    if listContains(villagers, role) then return "villager" end
    if listContains(werewolves, role) then return "werewolf" end
    return role -- Independent
end

function listContains(list, item)
    for _, value in pairs(list) do
        if value == item then
            return true
        end
    end

    return false
end

function endGame()
    client:setGameName(nil)
    init()
end 

client:on('guildAvailable', function(guild)
    print('Joined guild ' .. guild.name .. ' (' .. guild.joinedAt .. ')')

    for channel in guild.textChannels do
        if channel.name == 'plaza-chat' then
            gameChannel = channel
            break
        end
    end
    print('Observing channel #' .. gameChannel.name)
end)

client:on('ready', function()
    print('Logged in as ' .. fullUserName(client.user))
end)

client:on('messageCreate', function(message)
    local content = string.gmatch(message.content, '%S+')
    local command = {}
    local userName = message.author.name
    local fullUserName = fullUserName(message.author)

    for token in content do -- tokenize user message
        command[#command + 1] = token
    end

    if command[1] == '!onenight' then
        if gameState == 'idle' then
            gameState = 'starting'
            messagePlaza('__***One Night Ultimate Werewolf***__ game started by ' .. userName .. '.\n'
            .. '@here: Use !join if you want to play! Game will start in ' .. waitTime / 1000 ..' seconds.')
            addPlayer(message.author)
            coroutine.wrap(function()
                timer.sleep(waitTime)
                startGame()
            end)()
        end
    end

    if command[1] == '!join' then
        if gameState == 'starting' then
            addPlayer(message.author)
        end
    end

    if command[1] == '!ping' then
        message.channel:sendMessage('!pong')
    end

    if command[1] == '!divine' then
        if gameState == "seer" and playerRoles["seer"][1] == message.author then
            local _, userToDivine = stringToPlayer(command[2])

            if userToDivine ~= nil then
                message.author.target = userToDivine
                messageUser(message.author, "You will divine **".. userToDivine.name .."**'s role in this kerfuffle.")
            else
                messageUser(message.author, "I do not know who that is. Are they currently playing? Usage: `!divine *nickname*`")
            end
        else
            messageUser(message.author, "A seer can use this command during their turn at night.")
        end
    end

    if command[1] == '!divine2' then
        if gameState == "seer" and playerRoles["seer"][1] == message.author then
            message.author.target = nil
            messageUser("You will divine two roles that are *NOT* currently in play.")
        else
            messageUser(message.author, "A seer can use this command during their turn at night.")
        end
    end

    if command[1] == '!rob' then
        if gameState == "robber" and playerRoles["robber"][1] == message.author then
            local _, victim = stringToPlayer(command[2])

            if victim ~= nil then
                message.author.target = victim
                messageUser(message.author, "You will swap roles with **".. victim.name .."**.")
            else
                messageUser(message.author, "I do not know who that is. Are they currently playing? Usage: `!rob *nickname*`")
            end
        else
            messageUser(message.author, "A robber can use this command during their turn at night.")
        end
    end

    if command[1] == '!vote' then
        if gameState == "eve" and isPlayer(message.author) then
            local _, victim = stringToPlayer(command[2])

            if victim ~= nil then
                votes[fullUserName] = victim
                messageUser(message.author, "Yes, let us slay ".. victim.name .." where they stand!")
            else
                messageUser(message.author, "I do not know who that is. Are they currently playing? Usage: `!vote *nickname*`")
            end
        else
            messageUser(message.author, "Players can vote on who they want to hang in the evening.")
        end
    end

    if command[1] == '!novote' then
        if gameState == "eve" and isPlayer(message.author) then
            votes[fullUserName] = nil
            messageUser(message.author, "Voting for nobody, eh? If you say so...")
        end
    end

    if command[1] == '!players' then
        if #players > 0 then
            local message = '```Player list:\n'
            for idx, player in pairs(players) do
                local user = player.user
                message = message .. idx .. '\t' .. ' ' .. user.name .. '#' .. user.discriminator .. '\n'
            end
            message = message .. '```'
            messagePlaza(message)
        else
            messagePlaza('There are currently no players.')
        end
    end

    -- Admin commands
    if isAdmin(message.author) then
        if command[1] == '!remove' then
            local idx, player = stringToPlayer(command[2])
            
            if idx ~= nil and player ~= nil then
                table.remove(players, idx)
                messagePlaza("Removed player " .. player.name .. "#" .. player.discriminator)
            else
                messagePlaza("Could not find player.")
            end
        end

        if command[1] == '!atu' then
            local repeatTimes = command[2]
            if repeatTimes == nil then 
                repeatTimes = 1 
            else
                repeatTimes = tonumber(repeatTimes)
            end

            while repeatTimes > 0 do
                addPlayer(getTestUser())
                repeatTimes = repeatTimes - 1
            end
        end

        if command[1] == '!end' then
            messagePlaza("**Game ended** by admin ".. message.author.name)
            endGame()
        end

        if command[1] == '!quit' then
            messagePlaza('!quit recieved from ' .. fullUserName .. ' in #' .. message.channel.name)
            client:stop(true)
        end
    end
end)

function messagePlaza(message)
    print('-- ' .. gameChannel.name .. ': ' .. message)
    gameChannel:sendMessage(message)
end

function messageUser(user, message)
    print('-- ' .. user.name .. ': ' .. message)
    if not user.isBot then
        user:sendMessage(message)
    end
end

function fullUserName(user)
    return string.format('%s#%s', user.name, user.discriminator)
end

function stringToPlayer(str)
    local name, number

    if (str == nil) then return nil end

    local seperatorIdx = str:find('#')

    if seperatorIdx == nil then
        name = str
    else
        name = str:sub(0, seperatorIdx-1)
        number = str:sub(seperatorIdx+1)
    end

    for i, user in ipairs(players) do
        if string.lower(name) == string.lower(user.name) and (number == nil or number == user.discriminator) then
            return i, user
        end
    end

    return nil -- Player not found
end

function isAdmin(user)
    if user.name == "Grognak" and user.discriminator == "6676" then
        return true
    end

    return false
end

function isPlayer(usr)
    for _, player in pairs(players) do
        if usr == player then
            return true
        end
    end

    return false
end


function getTestUser()
    local adjective = getAdjective()
    local animal = getAnimal()
    local number = string.format('%04d', math.random(9999))

    local user = {
        name = adjective .. animal,
        discriminator = number,

        isBot = true
    }

    return user
end

function getAdjective()
    local adjectives = {
        'Busy',
        'Lazy',
        'Careless',
        'Clumsy',
        'Meek',
        'Dull',
        'Scared',
        'Cowardly',
        'Rude',
        'Selfish',
        'Adorable',
        'Glowing',
        'Sloppy',
        'Messy',
        'Creepy',
        'Foul',
        'Greedy',
        'Happy',
        'Angry',
        'Puny',
    }

    return adjectives[math.random(#adjectives)]
end

function getAnimal()
    local animals = {
        'Dog',
        'Cat',
        'Horse',
        'Dragon',
        'Lizard',
        'Chinchilla',
        'Hedgehog',
        'Crocodile',
        'Scorpion',
        'Snake',
        'Tarantula',
        'Cockroach',
        'Iguana',
        'Crab',
        'Donkey',
        'Squirrel',
        'Goat',
        'Monkey',
        'Pig',
    }

    return animals[math.random(#animals)]
end

-- Main starts here
init()

local fd = files.open('token.txt', 'r', '0644', function (err, fd)
    if (err) then
        print('Could not open token file for reading.')
        print('Please create a token.txt file in the same directory as werewolf.lua, and')
        print('put inside of it your "App Bot User" token from https://discordapp.com/developers/applications/me')
        os.exit(1)
    end

    local buffer = files.readSync(fd)
    files.close(fd)

    print('Using token: ' .. buffer)
    client:run(buffer)
end)