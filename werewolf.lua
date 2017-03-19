local discordia = require('discordia')
local files = require('fs')
local timer = require('timer')

local client = discordia.Client()

local gameChannel = nil

local waitTime = 10
local gameState = 'idle'
local players = {}

function addPlayer(usr)
    for idx, player in pairs(players) do -- make sure they're not already in
        local other = player.user
        if other.name == usr.name and other.discriminator == usr.discriminator then
            usr:sendMessage('You have already been added to this game.')
            return
        end
    end

    local player = {
        user = usr,
        team = 'village',
        role = 'villager',

        isBot = false
    }

    table.insert(players, player)

    messagePlaza('Added player ' .. fullUserName(usr) .. ' (total: ' .. #players .. ')')
end

function startGame()
    if #players < 3 then
        messagePlaza('There must be at least 3 people to start a game.')
        endGame()
    else
        assignRoles()

        gameState = 'started'
        messagePlaza('Game started with potential roles:\n'
        .. '2 werewolves, 1 seer, 1 robber, 1 troublemaker, ' .. #players - 2 .. ' villagers')


        endGame()
    end
end

function assignRoles()
    local rolePool = {
        {
            team = 'werewolf',
            role = 'werewolf'
        },
        {
            team = 'werewolf',
            role = 'werewolf'
        },
        {
            team = 'village',
            role = 'seer'
        },
        {
            team = 'village',
            role = 'robber'
        },
        {
            team = 'village',
            role = 'troublemaker'
        },
    }
    local villagers = #players - 2
    while villagers > 0 do
        table.insert(rolePool, {team='village', role='villager'})
        villagers = villagers - 1
    end

    local randomRolePool = {}
    while #rolePool > 0 do
        local idx = math.random(#rolePool)
        table.insert(randomRolePool, rolePool[idx])
        table.remove(rolePool, idx)
    end

    for i, player in ipairs(players) do
        player.team = randomRolePool[i].team
        player.role = randomRolePool[i].role
        
        if not player.user.isBot then
            player.user:sendMessage('You are a **'.. player.role ..'** on the **' .. player.team .. '** team.')
        end
    end
end

function endGame()
    gameState = 'idle'
    players = {}

    messagePlaza('Ending game')
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
            .. '@here: Use !join if you want to play! Game will start in ' .. waitTime ..' seconds.')
            addPlayer(message.author)
            coroutine.wrap(function()
                timer.sleep(waitTime * 1000)
                startGame()
            end)()
        end
    end

    if command[1] == '!join' then
        if gameState == 'starting' then
            addPlayer(message.author)
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

    if command[1] == '!remove' then
        local rName = command[2]
        local rDisc = command[3]
        local playerFound = false

        for idx, player in ipairs(players) do
            local user = player.user
            if string.lower(user.name) == string.lower(rName) and (rDisc == nil or rDisc == user.discriminator) then
                rName = user.name -- for text case
                if rDisc == nil then
                    rDisc = user.discriminator
                end

                playerFound = true
                    
                table.remove(players, idx)
                break
            end
        end

        if playerFound then
            messagePlaza('Removed player ' .. rName .. '#' .. rDisc)
        else   
            messagePlaza('Could not find player.')
        end
    end

    if command[1] == '!quit' then
        messagePlaza('!quit recieved from ' .. fullUserName .. ' in #' .. message.channel.name)
        client:stop(true)
    end

    if command[1] == '!ping' then
        message.channel:sendMessage('!pong')
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
end)

function messagePlaza(message)
    print('-- ' .. message)
    gameChannel:sendMessage(message)
end

function fullUserName(user)
    return string.format('%s#%s', user.name, user.discriminator)
end

function getTestUser()
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
        'King'
    }

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
        'Pig'
    }

    local adjective = adjectives[math.random(#adjectives)]
    local animal = animals[math.random(#animals)]
    local number = string.format('%04d', math.random(9999))

    local user = {
        name = adjective .. animal,
        discriminator = number,

        isBot = true
    }

    return user
end

-- Main starts here
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