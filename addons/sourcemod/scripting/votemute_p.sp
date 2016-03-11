#include <sourcemod>
#include <sdktools>
#include <sourcecomms>
#include <nd_stocks>

#undef REQUIRE_PLUGIN
#tryinclude <adminmenu>
#tryinclude <updater>

#define PLUGIN_VERSION "1.0.6"

/* Auto Updater */
#if defined _updater_included
#define UPDATE_URL  "https://github.com/stickz/Redstone/raw/build/updater/votemute_p/votemute_p.txt"

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "updater"))
        Updater_AddPlugin(UPDATE_URL);
}
#endif

ConVar g_Cvar_Limits;
ConVar g_Cvar_Admins;
ConVar g_Cvar_Duration;

new Handle:g_hVoteMenu = INVALID_HANDLE;

#define VOTE_CLIENTID	0
#define VOTE_USERID		1
#define VOTE_NAME		0
#define VOTE_NO 		"###no###"
#define VOTE_YES 		"###yes###"

#define VOTE_TYPE_GAG 0
#define VOTE_TYPE_MUTE 1
#define VOTE_TYPE_SILENCE 2

#define INVALID_TARGET -1

new g_voteClient[2];
new String:g_voteInfo[3][65];

new g_votetype = 0;

//new bool:g_Gagged[65]

public Plugin:myinfo =
{
	name = "Vote Mute/Vote Silence",
	author = "<eVa>Dog edited by Stickz",
	description = "Vote Muting and Silencing",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
}

public OnPluginStart()
{
	CreateConVar("sm_votemute_version", PLUGIN_VERSION, "Version of votemute/votesilence", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_Cvar_Limits = CreateConVar("sm_votemute_limit", "0.51", "percent required for successful mute vote or mute silence.");
	g_Cvar_Admins = CreateConVar("sm_votemute_adminonly", "0", "1= admins only, 0 = regular players allowed");
	g_Cvar_Duration = CreateConVar("sm_votemute_duration", "60", "set punishment duration, 0 = permanent");
	
	AutoExecConfig(true, "votemute_p");
	
	//Allowed for ALL players
	RegConsoleCmd("sm_votemute", Command_Votemute,  "sm_votemute <player> ");  
	RegConsoleCmd("sm_votesilence", Command_Votesilence,  "sm_votesilence <player> ");  
	RegConsoleCmd("sm_votegag", Command_Votegag,  "sm_votegag <player> "); 
	
	//RegConsoleCmd("say", Command_Say);
	//RegConsoleCmd("say_team", Command_Say);
	//RegConsoleCmd("voicemenu", Command_VoiceMenu)
	
	LoadTranslations("common.phrases");
	
	#if defined _updater_included
	if (LibraryExists("updater"))
        Updater_AddPlugin(UPDATE_URL);
	#endif
}

/*public Action:Command_Say(client, args)
{
	if (client)
	{
		if (g_Gagged[client])
		{
			return Plugin_Handled;		
		}
	}
	
	return Plugin_Continue;
}

public Action:Command_VoiceMenu(client, args)
{
	if (client)
	{
		if (g_Gagged[client])
		{
			return Plugin_Handled	
		}
	}
	return Plugin_Continue
}*/

	
public Action:Command_Votemute(client, args)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return Plugin_Handled;
	}	
	
	if (!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}
	
	if (g_Cvar_Admins.BoolValue && !IsValidAdmin(client, "k"))
	{
		ReplyToCommand(client, "[xG] This command is for server moderators only.");
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		g_votetype = VOTE_TYPE_MUTE;
		DisplayVoteTargetMenu(client);
	}
	else
	{
		new String:arg[64];
		GetCmdArg(1, arg, 64);
		
		new target = FindTarget(client, arg);

		if (target == INVALID_TARGET)
		{
			return Plugin_Handled;
		}
		
		else if (SourceComms_GetClientMuteType(target) != bNot)
		{
			PrintToChat(client, "\x05[xG] This client is already muted!");
			return Plugin_Handled;
		}
		else if (isSilenced(client))
		{
			PrintToChat(client, "\x05[xG] You cannot use this feature while silenced!");
			return Plugin_Handled;				
		}
		
		g_votetype = VOTE_TYPE_MUTE;
		DisplayVoteMuteMenu(client, target);
	}
	
	return Plugin_Handled;
}

public Action:Command_Votesilence(client, args)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return Plugin_Handled;
	}	
	
	if (!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}
	
	if (g_Cvar_Admins.BoolValue && !IsValidAdmin(client, "k"))
	{
		ReplyToCommand(client, "[xG] This command is for server moderators only.");
		return Plugin_Handled;
	}
	
	
	if (args < 1)
	{
		g_votetype = VOTE_TYPE_SILENCE;
		DisplayVoteTargetMenu(client);
	}
	else
	{
		new String:arg[64];
		GetCmdArg(1, arg, 64);
		
		new target = FindTarget(client, arg);

		if (target == INVALID_TARGET)
			return Plugin_Handled;

		else if (isSilenced(target))
		{
			PrintToChat(client, "\x05[xG] This client is already silenced!");
			return Plugin_Handled;		
		}
		else if (isSilenced(client))
		{
			PrintToChat(client, "\x05[xG] You cannot use this feature while silenced!");
			return Plugin_Handled;				
		}
		
		g_votetype = VOTE_TYPE_SILENCE;
		DisplayVoteMuteMenu(client, target);
	}
	return Plugin_Handled;
}

public Action:Command_Votegag(client, args)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return Plugin_Handled;
	}

	if (g_Cvar_Admins.BoolValue && !IsValidAdmin(client, "k"))
	{
		ReplyToCommand(client, "[xG] This command is for server moderators only.");
		return Plugin_Handled;
	}		
	
	if (!TestVoteDelay(client))
	{
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		g_votetype = VOTE_TYPE_GAG;
		DisplayVoteTargetMenu(client);
	}
	else
	{
		new String:arg[64];
		GetCmdArg(1, arg, 64);
		
		new target = FindTarget(client, arg);

		if (target == INVALID_TARGET)
		{
			return Plugin_Handled;
		}
		
		else if (SourceComms_GetClientGagType(target) != bNot)
		{
			PrintToChat(client, "\x05[xG] This client is already gagged!");
			return Plugin_Handled;
		}
		else if (isSilenced(client))
		{
			PrintToChat(client, "\x05[xG] You cannot use this feature while silenced!");
			return Plugin_Handled;				
		}
		
		g_votetype = VOTE_TYPE_GAG;
		DisplayVoteMuteMenu(client, target);
	}
	return Plugin_Handled;
}

DisplayVoteMuteMenu(client, target)
{
	g_voteClient[VOTE_CLIENTID] = target;
	g_voteClient[VOTE_USERID] = GetClientUserId(target);

	GetClientName(target, g_voteInfo[VOTE_NAME], sizeof(g_voteInfo[]));
	
	decl String:Name[8];
	
	switch (g_votetype)
	{
		case VOTE_TYPE_MUTE: 	Format(Name, sizeof(Name), "Mute");
		case VOTE_TYPE_GAG:  	Format(Name, sizeof(Name), "Gag");
		case VOTE_TYPE_SILENCE: Format(Name, sizeof(Name), "Silence");	
	}
	
	decl String:Message[64];
	Format(Message, sizeof(Message), "\"%L\" initiated a %s vote against \"%L\"", client, Name, target);
	
	PrintToAdmins(Message, "a");
	LogAction(client, target, Message);
	
	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	SetMenuTitle(g_hVoteMenu, "%s Player:", Name);	
	AddMenuItem(g_hVoteMenu, VOTE_YES, "Yes");
	AddMenuItem(g_hVoteMenu, VOTE_NO, "No");
	SetMenuExitButton(g_hVoteMenu, false);
	VoteMenuToAll(g_hVoteMenu, 20);
}

DisplayVoteTargetMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_Vote);
	
	decl String:title[100];
	new String:playername[128]
	new String:identifier[64]
	Format(title, sizeof(title), "%s", "Choose player:");
	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	for (new i = 1; i < GetMaxClients(); i++)
	{
		if (IsClientInGame(i) && !(GetUserFlagBits(i) & ADMFLAG_CHAT))
		{
			GetClientName(i, playername, sizeof(playername))
			Format(identifier, sizeof(identifier), "%i", i)
			AddMenuItem(menu, identifier, playername)
		}
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}


public MenuHandler_Vote(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End: CloseHandle(menu);
		case MenuAction_Select:
		{
			decl String:info[32], String:name[32];
			new target;
			
			GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
			target = StringToInt(info);

			if (target == 0)
				PrintToChat(param1, "[SM] %s", "Player no longer available");

			else
				DisplayVoteMuteMenu(param1, target);	
		}
	}
}

public Handler_VoteCallback(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End: VoteMenuClose();
		
		case MenuAction_Display:
		{
			decl String:title[64];
			GetMenuTitle(menu, title, sizeof(title));
			
			decl String:buffer[255];
			Format(buffer, sizeof(buffer), "%s %s", title, g_voteInfo[VOTE_NAME]);

			new Handle:panel = Handle:param2;
			SetPanelTitle(panel, buffer);		
		}
		
		case MenuAction_DisplayItem:
		{
			decl String:display[64];
			GetMenuItem(menu, param2, "", 0, _, display, sizeof(display));
		 
			if (strcmp(display, "No") == 0 || strcmp(display, "Yes") == 0)
			{
				decl String:buffer[255];
				Format(buffer, sizeof(buffer), "%s", display);

				return RedrawMenuItem(buffer);
			}		
		}
		//case MenuAction_Select: VoteSelect(menu, param1, param2);
		
		case MenuAction_VoteCancel:
		{
			if (param1 == VoteCancel_NoVotes)	
				PrintToChatAll("[SM] %s", "No Votes Cast");
		}
		
		case MenuAction_VoteEnd:
		{
			decl String:item[64], String:display[64];
			new Float:percent, Float:limit, votes, totalVotes;

			GetMenuVoteInfo(param2, votes, totalVotes);
			GetMenuItem(menu, param1, item, sizeof(item), _, display, sizeof(display));
			
			if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
				votes = totalVotes - votes; // Reverse the votes to be in relation to the Yes option.
			
			percent = GetVotePercent(votes, totalVotes);
			
			limit = g_Cvar_Limits.FloatValue;
			
			if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
			{
				LogAction(-1, -1, "Vote failed.");
				PrintToChatAll("[SM] %s", "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
			}
			else
			{
				PrintToChatAll("[SM] %s", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);			
				
				switch (g_votetype)
				{
					case VOTE_TYPE_MUTE:
					{
						PrintToChatAll("[SM] %s", "Muted target", "_s", g_voteInfo[VOTE_NAME]);
						LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote mute successful, muted \"%L\" ", g_voteClient[VOTE_CLIENTID]);
						SourceComms_SetClientMute(g_voteClient[VOTE_CLIENTID], true, g_Cvar_Duration.IntValue, true, "Voted by players");
					}
					
					case VOTE_TYPE_GAG:
					{
						PrintToChatAll("[SM] %s", "Gagged target", "_s", g_voteInfo[VOTE_NAME]);	
						LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote gag successful, gagged \"%L\" ", g_voteClient[VOTE_CLIENTID]);
						SourceComms_SetClientGag(g_voteClient[VOTE_CLIENTID], true, g_Cvar_Duration.IntValue, true, "Voted by players");						
					}
					
					case VOTE_TYPE_SILENCE:
					{
						PrintToChatAll("[SM] %s", "Silenced target", "_s", g_voteInfo[VOTE_NAME]);	
						LogAction(-1, g_voteClient[VOTE_CLIENTID], "Vote silence successful, silenced \"%L\" ", g_voteClient[VOTE_CLIENTID]);
						SourceComms_SetClientGag(g_voteClient[VOTE_CLIENTID], true, g_Cvar_Duration.IntValue, true, "Voted by players");
						SourceComms_SetClientMute(g_voteClient[VOTE_CLIENTID], true, g_Cvar_Duration.IntValue, true, "Voted by players");					
					}				
				}
			}		
		}	
	}
	return 0;	
}

bool:isSilenced(client)
{
	return SourceComms_GetClientMuteType(client) != bNot && SourceComms_GetClientGagType(client) != bNot;
}

VoteMenuClose()
{
	CloseHandle(g_hVoteMenu);
	g_hVoteMenu = INVALID_HANDLE;
}

Float:GetVotePercent(votes, totalVotes)
{
	return FloatDiv(float(votes),float(totalVotes));
}

bool:TestVoteDelay(client)
{
 	new delay = CheckVoteDelay();
 	
 	if (delay > 0)
 	{
 		if (delay > 60)
 			ReplyToCommand(client, "[SM] Vote delay: %i mins", delay % 60);

 		else
 			ReplyToCommand(client, "[SM] Vote delay: %i secs", delay);
 		
 		return false;
 	}
 	
	return true;
}