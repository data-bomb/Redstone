#include <sourcemod>
#include <sdktools>
#include <nd_stocks>

#pragma semicolon 1

#undef REQUIRE_PLUGIN
#tryinclude <multicolors>
#if !defined _mutlicolors_included
	#tryinclude <morecolors>
#endif
#if ((!defined _mutlicolors_included) && (!defined _colors_included))
	#tryinclude <colors>
#endif
#tryinclude <updater>
#define REQUIRE_PLUGIN

/* Auto Updater */
#define UPDATE_URL	"https://github.com/stickz/Redstone/blob/build/updater/afk_manager4/translations/afk_manager.phrases.txt"
#include "updater/standard.sp"

// Defines
#define AFK_WARNING_INTERVAL						5
#define AFK_CHECK_INTERVAL							1.0

#if !defined MAX_MESSAGE_LENGTH
	#define MAX_MESSAGE_LENGTH						250
#endif

#define SECONDS_IN_DAY								86400

#define ND_TRANSPORT_GATE 2
#define ND_TRANSPORT_NAME "struct_transport_gate"

#define LOG_FOLDER									"logs"
#define LOG_PREFIX									"afkm_"
#define LOG_EXT										"log"

// ConVar Defines
#define CONVAR_ENABLED								1
#define CONVAR_MOD_AFK								2
#define CONVAR_PREFIXSHORT							3
#define CONVAR_PREFIXCOLORS							4
#define CONVAR_LANGUAGE								5
#define CONVAR_LOG_WARNINGS							6
#define CONVAR_TIMETOMOVE							7
#define CONVAR_TIMETOKICK							8
#define CONVAR_EXCLUDEDEAD							9

// Arrays
char AFKM_LogFile[PLATFORM_MAX_PATH]; // Log File
//Handle g_FWD_hPlugins =								INVALID_HANDLE; // Forward Plugin Handles
Handle g_hAFKTimer[MAXPLAYERS+1] =					{INVALID_HANDLE, ...}; // AFK Timers
int g_iAFKTime[MAXPLAYERS+1] =						{-1, ...}; // Initial Time of AFK
int g_iSpawnTime[MAXPLAYERS+1] =					{-1, ...}; // Time of Spawn
int iButtons[MAXPLAYERS+1] = 						{0, ...}; // Bitsum of buttons pressed
int g_iPlayerTeam[MAXPLAYERS+1] =					{-1, ...}; // Player Team
int iPlayerAttacker[MAXPLAYERS+1] =					{-1, ...}; // Player Attacker
int iObserverMode[MAXPLAYERS+1] =					{-1, ...}; // Observer Mode
int iObserverTarget[MAXPLAYERS+1] =					{-1, ...}; // Observer Target
//int iMouse[MAXPLAYERS+1][2]; // X = Vertical, Y = Horizontal
bool bPlayerAFK[MAXPLAYERS+1] =						{true, ...}; // Player AFK Status
bool bPlayerDeath[MAXPLAYERS+1] =					{false, ...};
float fEyeAngles[MAXPLAYERS+1][3]; // X = Vertical, Y = Height, Z = Horizontal

bool bCvarIsHooked[11] =							{false, ...}; // Console Variable Hook Status

// Global Variables
bool g_bLateLoad = 									false;
// Console Related Variables
bool g_bEnabled =									false;
char g_sPrefix[] =									"AFK Manager";
#if defined _colors_included
bool g_bPrefixColors =								false;
#endif
bool g_bForceLanguage =								false;
bool g_bLogWarnings =								false;
bool g_bExcludeDead =								false;
int g_iTimeToMove =									-1;
int g_iTimeToKick =									-1;

// Status Variables
bool bMovePlayers =									true;
bool bKickPlayers =									true;
bool g_bWaitRound =									true;

// Spectator Related Variables
int g_iSpec_Team =									1;
int g_iSpec_FLMode =								0;

// Mod Based Console Variables
Handle hCvarAFK =									INVALID_HANDLE;

// Handles
// Forwards
Handle g_FWD_hOnAFKEvent =							INVALID_HANDLE;
Handle g_FWD_hOnClientAFK =							INVALID_HANDLE;
Handle g_FWD_hOnClientBack =						INVALID_HANDLE;

// AFK Manager Console Variables
Handle hCvarEnabled =								INVALID_HANDLE;
Handle hCvarPrefixShort =							INVALID_HANDLE;
#if defined _colors_included
Handle hCvarPrefixColor =							INVALID_HANDLE;
#endif
Handle hCvarLanguage =								INVALID_HANDLE;
Handle hCvarLogWarnings =							INVALID_HANDLE;
Handle hCvarLogMoves =								INVALID_HANDLE;
Handle hCvarLogKicks =								INVALID_HANDLE;
Handle hCvarLogDays =								INVALID_HANDLE;
Handle hCvarMinPlayersMove =						INVALID_HANDLE;
Handle hCvarMinPlayersKick =						INVALID_HANDLE;
Handle hCvarAdminsImmune =							INVALID_HANDLE;
Handle hCvarAdminsFlag =							INVALID_HANDLE;
Handle hCvarMoveSpec =								INVALID_HANDLE;
Handle hCvarMoveAnnounce =							INVALID_HANDLE;
Handle hCvarTimeToMove =							INVALID_HANDLE;
Handle hCvarWarnTimeToMove =						INVALID_HANDLE;
Handle hCvarKickPlayers =							INVALID_HANDLE;
Handle hCvarKickAnnounce =							INVALID_HANDLE;
Handle hCvarTimeToKick =							INVALID_HANDLE;
Handle hCvarWarnTimeToKick =						INVALID_HANDLE;
Handle hCvarSpawnTime =								INVALID_HANDLE;
Handle hCvarWarnSpawnTime =							INVALID_HANDLE;
Handle hCvarExcludeDead =							INVALID_HANDLE;
Handle hCvarWarnUnassigned =						INVALID_HANDLE;

// Plugin Information
public Plugin myinfo =
{
    name = "[ND] AFK Manager",
    author = "Rothgar, Stickz",
    description = "Takes action on AFK players",
    version = "dummy",
    url = "https://github.com/stickz/Redstone/"
};

// API
void API_Init()
{
	CreateNative("AFKM_IsClientAFK", Native_IsClientAFK);
	CreateNative("AFKM_GetClientAFKTime", Native_GetClientAFKTime);
	//g_FWD_hOnAFKEvent = CreateForward(ET_Event, Param_String, Param_Cell);
	g_FWD_hOnAFKEvent = CreateGlobalForward("AFKM_OnAFKEvent", ET_Event, Param_String, Param_Cell);
	g_FWD_hOnClientAFK = CreateGlobalForward("AFKM_OnClientAFK", ET_Ignore, Param_Cell);
	g_FWD_hOnClientBack = CreateGlobalForward("AFKM_OnClientBack", ET_Ignore, Param_Cell);
}

// Natives
public int Native_IsClientAFK(Handle plugin, int numParams) // native bool AFKM_IsClientAFK(int client);
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	else
		return bPlayerAFK[client];
}

public int Native_GetClientAFKTime(Handle plugin, int numParams) // native int AFKM_GetClientAFKTime(int client);
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	else if (g_iAFKTime[client] == -1)
		return g_iAFKTime[client];
	else
		return (GetTime() - g_iAFKTime[client]);
}

// Forwards
void Forward_OnClientAFK(int client) // forward void AFKM_OnClientAFK(int client);
{
	Call_StartForward(g_FWD_hOnClientAFK); // Start Forward
	Call_PushCell(client);
	Call_Finish();
}

void Forward_OnClientBack(int client) // forward void AFKM_OnClientBack(int client);
{
	Call_StartForward(g_FWD_hOnClientBack); // Start Forward
	Call_PushCell(client);
	Call_Finish();
}

Action Forward_OnAFKEvent(const char[] name, int client) // forward Action AFKM_OnAFKEvent(const char[] name, int client);
{
	Action result;

	Call_StartForward(g_FWD_hOnAFKEvent); // Start Forward
	Call_PushString(name);
	Call_PushCell(client);
	Call_Finish(result);

	return result;
}


// Log Functions
void BuildLogFilePath() // Build Log File System Path
{
	char sLogPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sLogPath, sizeof(sLogPath), LOG_FOLDER);

	if ( !DirExists(sLogPath) ) // Check if SourceMod Log Folder Exists Otherwise Create One
		CreateDirectory(sLogPath, 511);

	char cTime[64];
	FormatTime(cTime, sizeof(cTime), "%Y%m%d");

	char sLogFile[PLATFORM_MAX_PATH];
	sLogFile = AFKM_LogFile;

	BuildPath(Path_SM, AFKM_LogFile, sizeof(AFKM_LogFile), "%s/%s%s.%s", LOG_FOLDER, LOG_PREFIX, cTime, LOG_EXT);

	if (!StrEqual(AFKM_LogFile, sLogFile))
		LogAction(0, -1, "[AFK Manager] Log File: %s", AFKM_LogFile);
}

void PurgeOldLogs() // Purge Old Log Files
{
	char sLogPath[PLATFORM_MAX_PATH];
	char buffer[256];
	Handle hDirectory = INVALID_HANDLE;
	FileType type = FileType_Unknown;

	BuildPath(Path_SM, sLogPath, sizeof(sLogPath), LOG_FOLDER);

	if ( DirExists(sLogPath) )
	{
		hDirectory = OpenDirectory(sLogPath);
		if (hDirectory != INVALID_HANDLE)
		{
			int iTimeOffset = GetTime() - ((SECONDS_IN_DAY * GetConVarInt(hCvarLogDays)) + 30);
			while ( ReadDirEntry(hDirectory, buffer, sizeof(buffer), type) )
			{
				if (type == FileType_File)
				{
					if (StrContains(buffer, LOG_PREFIX, false) != -1)
					{
						char file[PLATFORM_MAX_PATH];
						Format(file, sizeof(file), "%s/%s", sLogPath, buffer);

						if ( GetFileTime(file, FileTime_LastChange) < iTimeOffset ) // Log file is old
							if (DeleteFile(file))
								LogAction(0, -1, "[AFK Manager] Deleted Old Log File: %s", file);
					}
				}
			}
		}
	}

	if (hDirectory != INVALID_HANDLE)
	{
		CloseHandle(hDirectory);
		hDirectory = INVALID_HANDLE;
	}
}

// Chat Functions
void AFK_PrintToChat(int client, const char[] sMessage, any:...)
{
	int iStart = client;
	int iEnd = MaxClients;

	if (client > 0)
		iEnd = client;
	else
		iStart = 1;

	char sBuffer[MAX_MESSAGE_LENGTH];

	for (int i = iStart; i <= iEnd; i++)
	{
		if (IsClientInGame(i))
		{
			if (g_bForceLanguage)
				SetGlobalTransTarget(LANG_SERVER);
			else
				SetGlobalTransTarget(i);
			VFormat(sBuffer, sizeof(sBuffer), sMessage, 3);
#if defined _colors_included
			if (g_bPrefixColors)
				CPrintToChat(i, "{olive}[{green}%s{olive}] {default}%s", g_sPrefix, sBuffer);
			else
				PrintToChat(i, "[%s] %s", g_sPrefix, sBuffer);
#else
			PrintToChat(i, "[%s] %s", g_sPrefix, sBuffer);
#endif
		}
	}
}


// Native Functions
/*
int GetMaxPlugins()
{
	return GetArraySize(g_FWD_hPlugins);
}

void AddPlugin(Handle plugin)
{
	int maxPlugins = GetMaxPlugins();
	for (int i = 0; i < maxPlugins; i++)
		if (plugin == GetArrayCell(g_FWD_hPlugins, i)) // Plugin Already Exists?
			return;

	PushArrayCell(g_FWD_hPlugins, plugin);
}


void RemovePlugin(Handle plugin)
{
	int maxPlugins = GetMaxPlugins();
	for (int i = 0; i < maxPlugins; i++)
		if (plugin == GetArrayCell(g_FWD_hPlugins, i))
			RemoveFromArray(g_FWD_hPlugins, i);
}
*/


// General Functions
char ActionToString(Action action)
{
	char Action_Name[32];
	switch (action)
	{
		case Plugin_Continue:
			Action_Name = "Plugin_Continue";
		case Plugin_Changed:
			Action_Name = "Plugin_Changed";
		case Plugin_Handled:
			Action_Name = "Plugin_Handled";
		case Plugin_Stop:
			Action_Name = "Plugin_Stop";
		default:
			Action_Name = "Plugin_Error";
	}
	return Action_Name;
}

bool IsValidClient(int client, bool nobots = true) // Check If A Client ID Is Valid
{
    if (client <= 0 || client > MaxClients)
		return false;
	else if (!IsClientConnected(client))
        return false;
	else if (IsClientSourceTV(client))
		return false;
	else if (nobots && IsFakeClient(client))
		return false;
    return IsClientInGame(client);
}

void ResetAttacker(int index)
{
	iPlayerAttacker[index] = -1;
}

void ResetSpawn(int index)
{
	g_iSpawnTime[index] =	-1;
}

void ResetObserver(int index)
{
	iObserverMode[index] = -1;
	iObserverTarget[index] = -1;
}

void ResetPlayer(int index, bool FullReset = true) // Player Resetting
{
	ResetSpawn(index);
	bPlayerAFK[index] = true;

	if (FullReset)
	{
		g_iAFKTime[index] = -1;
		g_iPlayerTeam[index] = -1;
		ResetAttacker(index);
		ResetObserver(index);
	}
	else
		g_iAFKTime[index] = GetTime();
}

void SetClientAFK(int client, bool Reset = true)
{
	if (Reset)
		ResetPlayer(client, false);
	else
		bPlayerAFK[client] = true;

	Forward_OnClientAFK(client);
}

void InitializePlayer(int index) // Player Initialization
{
	if (IsValidClient(index))
	{
		if (g_hAFKTimer[index] != INVALID_HANDLE) // Check Timers and Destroy Them?
		{
			CloseHandle(g_hAFKTimer[index]);
			g_hAFKTimer[index] = INVALID_HANDLE;
		}

		// Check Admin immunity
		bool FullImmunity = false;

		if (GetConVarInt(hCvarAdminsImmune) == 1)
			if (CheckAdminImmunity(index))
				FullImmunity = true;
		if (!FullImmunity)
		{
			g_iAFKTime[index] = GetTime();

			g_iPlayerTeam[index] = GetClientTeam(index);
			g_hAFKTimer[index] = CreateTimer(AFK_CHECK_INTERVAL, Timer_CheckPlayer, index, TIMER_REPEAT); // Create AFK Timer
		}
	}
}

void UnInitializePlayer(int index) // Player UnInitialization
{
	if (g_hAFKTimer[index] != INVALID_HANDLE) // Check for timers and destroy them?
	{
		CloseHandle(g_hAFKTimer[index]);
		g_hAFKTimer[index] = INVALID_HANDLE;
	}
	ResetPlayer(index);
}

int AFK_GetClientCount(bool inGameOnly = true)
{
	int clients = 0;
	for (int i = 1; i <= GetMaxClients(); i++)	
		if( ( ( inGameOnly ) ? IsClientInGame(i) : IsClientConnected(i) ) && !IsClientSourceTV(i) && !IsFakeClient(i) )
			clients++;
	return clients;
}

void CheckMinPlayers()
{
	int MoveMinPlayers = GetConVarInt(hCvarMinPlayersMove);
	int KickMinPlayers = GetConVarInt(hCvarMinPlayersKick);

	int players = AFK_GetClientCount();

	if (players >= MoveMinPlayers)
	{
		if (!bMovePlayers)
			if (g_bLogWarnings)
				LogToFile(AFKM_LogFile, "Player count for AFK Move minimum has been reached, feature is now enabled: sm_afk_move_min_players = %i Current Players = %i", MoveMinPlayers, players);
		bMovePlayers = true;
	}
	else
	{
		if (bMovePlayers)
			if (g_bLogWarnings)
				LogToFile(AFKM_LogFile, "Player count for AFK Move minimum is below requirements, feature is now disabled: sm_afk_move_min_players = %i Current Players = %i", MoveMinPlayers, players);
		bMovePlayers = false;
	}

	if (players >= KickMinPlayers)
	{
		if (!bKickPlayers)
			if (g_bLogWarnings)
				LogToFile(AFKM_LogFile, "Player count for AFK Kick minimum has been reached, feature is now enabled: sm_afk_kick_min_players = %i Current Players = %i", KickMinPlayers, players);
		bKickPlayers = true;
	}
	else
	{
		if (bKickPlayers)
			if (g_bLogWarnings)
				LogToFile(AFKM_LogFile, "Player count for AFK Kick minimum is below requirements, feature is now disabled: sm_afk_kick_min_players = %i Current Players = %i", KickMinPlayers, players);
		bKickPlayers = false;
	}
}

// Cvar Hooks
public void CvarChange_Status(Handle cvar, const char[] oldvalue, const char[] newvalue) // Hook ConVar Status
{
	if (!StrEqual(oldvalue, newvalue))
	{
		if (cvar == hCvarTimeToMove)
			g_iTimeToMove = StringToInt(newvalue);
		else if (cvar == hCvarTimeToKick)
			g_iTimeToKick = StringToInt(newvalue);
		else if (StringToInt(newvalue) == 1)
		{
			if (cvar == hCvarEnabled)
				EnablePlugin();
			else if (cvar == hCvarLanguage)
				g_bForceLanguage = true;
			else if (cvar == hCvarLogWarnings)
				g_bLogWarnings = true;
			else if (cvar == hCvarPrefixShort)
				g_sPrefix = "AFK";
			else if (cvar == hCvarExcludeDead)
				g_bExcludeDead = true;
#if defined _colors_included
			else if (cvar == hCvarPrefixColor)
				g_bPrefixColors = true;
#endif
		}
		else if (StringToInt(newvalue) == 0)
		{
			if (cvar == hCvarEnabled)
				DisablePlugin();
			else if (cvar == hCvarLanguage)
				g_bForceLanguage = false;
			else if (cvar == hCvarLogWarnings)
				g_bLogWarnings = false;
			else if (cvar == hCvarPrefixShort)
				g_sPrefix = "AFK Manager";
			else if (cvar == hCvarExcludeDead)
				g_bExcludeDead = false;
#if defined _colors_included
			else if (cvar == hCvarPrefixColor)
				g_bPrefixColors = false;
#endif
		}
	}
}

public void CvarChange_Locked(Handle cvar, const char[] oldvalue, const char[] newvalue) // Lock ConVar
{
	if ((cvar == hCvarAFK) && (StringToInt(newvalue) != 0))
		SetConVarInt(cvar, 0);
}

void HookEvents() // Event Hook Registrations
{
	HookEvent("player_team", Event_PlayerTeam);

	HookEvent("player_spawn", Event_PlayerSpawn);

	HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
	
	/* Added functions for Nuclear Dawn */
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("structure_death", Event_StructDeath);
}

void HookConVars() // ConVar Hook Registrations
{
	if (!bCvarIsHooked[CONVAR_ENABLED])
	{
		HookConVarChange(hCvarEnabled, CvarChange_Status); // Hook Enabled Variable
		bCvarIsHooked[CONVAR_ENABLED] = true;
	}
	
	if (hCvarAFK != INVALID_HANDLE)
	{
		if (!bCvarIsHooked[CONVAR_MOD_AFK])
		{
			HookConVarChange(hCvarAFK, CvarChange_Locked); // Hook AFK Variable
			bCvarIsHooked[CONVAR_MOD_AFK] = true;
			SetConVarInt(hCvarAFK, 0);
		}
	}
	
	if (!bCvarIsHooked[CONVAR_PREFIXSHORT])
	{
		HookConVarChange(hCvarPrefixShort, CvarChange_Status); // Hook Short Prefix Variable
		bCvarIsHooked[CONVAR_PREFIXSHORT] = true;

		if (GetConVarBool(hCvarPrefixShort))
			g_sPrefix = "AFK";
	}
#if defined _colors_included
	if (!bCvarIsHooked[CONVAR_PREFIXCOLORS])
	{
		HookConVarChange(hCvarPrefixColor, CvarChange_Status); // Hook Color Prefix Variable
		bCvarIsHooked[CONVAR_PREFIXCOLORS] = true;

		if (GetConVarBool(hCvarPrefixColor))
			g_bPrefixColors = true;
	}
#endif
	if (!bCvarIsHooked[CONVAR_LANGUAGE])
	{
		HookConVarChange(hCvarLanguage, CvarChange_Status); // Hook Language Variable
		bCvarIsHooked[CONVAR_LANGUAGE] = true;

		if (GetConVarBool(hCvarLanguage))
			g_bForceLanguage = true;
	}
	if (!bCvarIsHooked[CONVAR_LOG_WARNINGS])
	{
		HookConVarChange(hCvarLogWarnings, CvarChange_Status); // Hook Warnings Variable
		bCvarIsHooked[CONVAR_LOG_WARNINGS] = true;

		if (GetConVarBool(hCvarLogWarnings))
			g_bLogWarnings = true;
	}
	if (!bCvarIsHooked[CONVAR_TIMETOMOVE])
	{
		HookConVarChange(hCvarTimeToMove, CvarChange_Status); // Hook TimeToMove Variable
		bCvarIsHooked[CONVAR_TIMETOMOVE] = true;

		g_iTimeToMove = GetConVarInt(hCvarTimeToMove);
	}
	if (!bCvarIsHooked[CONVAR_TIMETOKICK])
	{
		HookConVarChange(hCvarTimeToKick, CvarChange_Status); // Hook TimeToKick Variable
		bCvarIsHooked[CONVAR_TIMETOKICK] = true;

		g_iTimeToKick = GetConVarInt(hCvarTimeToKick);
	}
	if (!bCvarIsHooked[CONVAR_EXCLUDEDEAD])
	{
		HookConVarChange(hCvarExcludeDead, CvarChange_Status); // Hook Exclude Dead Variable
		bCvarIsHooked[CONVAR_EXCLUDEDEAD] = true;

		if (GetConVarBool(hCvarExcludeDead))
			g_bExcludeDead = true;
	}
}

void RegisterCvars() // Cvar Registrations
{
	hCvarEnabled = CreateConVar("sm_afk_enable", "1", "Is the AFK Manager enabled or disabled? [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarPrefixShort = CreateConVar("sm_afk_prefix_short", "0", "Should the AFK Manager use a short prefix? [0 = FALSE, 1 = TRUE, DEFAULT: 0]", FCVAR_NONE, true, 0.0, true, 1.0);
#if defined _colors_included
	hCvarPrefixColor = CreateConVar("sm_afk_prefix_color", "1", "Should the AFK Manager use color for the prefix tag? [0 = DISABLED, 1 = ENABLED, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
#endif
	hCvarLanguage = CreateConVar("sm_afk_force_language", "0", "Should the AFK Manager force all message language to the server default? [0 = DISABLED, 1 = ENABLED, DEFAULT: 0]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarLogWarnings = CreateConVar("sm_afk_log_warnings", "1", "Should the AFK Manager log plugin warning messages. [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarLogMoves = CreateConVar("sm_afk_log_moves", "1", "Should the AFK Manager log client moves. [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarLogKicks = CreateConVar("sm_afk_log_kicks", "1", "Should the AFK Manager log client kicks. [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarLogDays = CreateConVar("sm_afk_log_days", "0", "How many days should we keep AFK Manager log files. [0 = INFINITE, DEFAULT: 0]");
	hCvarMinPlayersMove = CreateConVar("sm_afk_move_min_players", "4", "Minimum number of connected clients required for AFK move to be enabled. [DEFAULT: 4]");
	hCvarMinPlayersKick = CreateConVar("sm_afk_kick_min_players", "6", "Minimum number of connected clients required for AFK kick to be enabled. [DEFAULT: 6]");
	hCvarAdminsImmune = CreateConVar("sm_afk_admins_immune", "1", "Should admins be immune to the AFK Manager? [0 = DISABLED, 1 = COMPLETE IMMUNITY, 2 = KICK IMMUNITY, 3 = MOVE IMMUNITY]");
	hCvarAdminsFlag = CreateConVar("sm_afk_admins_flag", "", "Admin Flag for immunity? Leave Blank for any flag.");
	hCvarMoveSpec = CreateConVar("sm_afk_move_spec", "1", "Should the AFK Manager move AFK clients to spectator team? [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarMoveAnnounce = CreateConVar("sm_afk_move_announce", "1", "Should the AFK Manager announce AFK moves to the server? [0 = DISABLED, 1 = EVERYONE, 2 = ADMINS ONLY, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 2.0);
	hCvarTimeToMove = CreateConVar("sm_afk_move_time", "60.0", "Time in seconds (total) client must be AFK before being moved to spectator. [0 = DISABLED, DEFAULT: 60.0 seconds]");
	hCvarWarnTimeToMove = CreateConVar("sm_afk_move_warn_time", "30.0", "Time in seconds remaining, player should be warned before being moved for AFK. [DEFAULT: 30.0 seconds]");
	hCvarKickPlayers = CreateConVar("sm_afk_kick_players", "1", "Should the AFK Manager kick AFK clients? [0 = DISABLED, 1 = KICK ALL, 2 = ALL EXCEPT SPECTATORS, 3 = SPECTATORS ONLY]");
	hCvarKickAnnounce = CreateConVar("sm_afk_kick_announce", "1", "Should the AFK Manager announce AFK kicks to the server? [0 = DISABLED, 1 = EVERYONE, 2 = ADMINS ONLY, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 2.0);
	hCvarTimeToKick = CreateConVar("sm_afk_kick_time", "120.0", "Time in seconds (total) client must be AFK before being kicked. [0 = DISABLED, DEFAULT: 120.0 seconds]");
	hCvarWarnTimeToKick = CreateConVar("sm_afk_kick_warn_time", "30.0", "Time in seconds remaining, player should be warned before being kicked for AFK. [DEFAULT: 30.0 seconds]");
	hCvarSpawnTime = CreateConVar("sm_afk_spawn_time", "20.0", "Time in seconds (total) that player should have moved from their spawn position. [0 = DISABLED, DEFAULT: 20.0 seconds]");
	hCvarWarnSpawnTime = CreateConVar("sm_afk_spawn_warn_time", "15.0", "Time in seconds remaining, player should be warned for being AFK in spawn. [DEFAULT: 15.0 seconds]");
	hCvarExcludeDead = CreateConVar("sm_afk_exclude_dead", "0", "Should the AFK Manager exclude checking dead players? [0 = FALSE, 1 = TRUE, DEFAULT: 0]", FCVAR_NONE, true, 0.0, true, 1.0);
	hCvarWarnUnassigned = CreateConVar("sm_afk_move_warn_unassigned", "1", "Should the AFK Manager warn team 0 (Usually unassigned) players? (Disabling may not work for some games) [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
}

void RegisterCmds() // Command Hook & Registrations
{
	RegAdminCmd("sm_afk_spec", Command_Spec, ADMFLAG_KICK, "sm_afk_spec <#userid|name>");
}

void EnablePlugin() // Enable Plugin Function
{
	g_bEnabled = true;

	for(int i = 1; i <= MaxClients; i++) // Reset timers for all players
		InitializePlayer(i);

	CheckMinPlayers(); // Check we have enough minimum players
}

void DisablePlugin() // Disable Plugin Function
{
	g_bEnabled = false;

	for(int i = 1; i <= MaxClients; i++) // Stop timers for all players
		UnInitializePlayer(i);
}

public Action Command_Spec(int client, int args) // Admin Spectate Move Command
{
	if (args < 1)
	{
		ReplyToCommand(client, "[AFK Manager] Usage: sm_afk_spec <#userid|name>");
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		if (MoveAFKClient(target_list[i], false) == Plugin_Stop)
			if (g_hAFKTimer[target_list[i]] != INVALID_HANDLE)
			{
				CloseHandle(g_hAFKTimer[target_list[i]]);
				g_hAFKTimer[target_list[i]] = INVALID_HANDLE;
			}
	}

	if (tn_is_ml)
	{
		if (GetConVarBool(hCvarPrefixShort))
			ShowActivity2(client, "[AFK] ", "%t", "Spectate_Force", target_name);
		else
			ShowActivity2(client, "[AFK Manager] ", "%t", "Spectate_Force", target_name);
		LogToFile(AFKM_LogFile, "%L: %T", client, "Spectate_Force", LANG_SERVER, target_name);
	}
	else
	{
		if (GetConVarBool(hCvarPrefixShort))
			ShowActivity2(client, "[AFK] ", "%t", "Spectate_Force", "_s", target_name);
		else
			ShowActivity2(client, "[AFK Manager] ", "%t", "Spectate_Force", "_s", target_name);
		LogToFile(AFKM_LogFile, "%L: %T", client, "Spectate_Force", LANG_SERVER, "_s", target_name);
	}
	return Plugin_Handled;
}

// SourceMod Events
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late; // Detect Late Load
	API_Init(); // Initialize API
	RegPluginLibrary("afkmanager"); // Register Plugin
#if defined _colors_included
    MarkNativeAsOptional("GetUserMessageType");
#endif
	MarkNativeAsOptional("GetEngineVersion");
	return APLRes_Success;
}

public void OnPluginStart() // AFK Manager Plugin has started
{
	BuildLogFilePath();

	LoadTranslations("common.phrases");
	LoadTranslations("afk_manager.phrases");

	// Initialize Arrays
	//g_FWD_hPlugins = CreateArray();

	// Game Engine Detection
#if defined NEW_ENGINE_DETECTION
	if ( CanTestFeatures() && (GetFeatureStatus(FeatureType_Native, "GetEngineVersion") == FeatureStatus_Available) )
	{
		new EngineVersion:g_EngineVersion = Engine_Unknown;

		g_EngineVersion = GetEngineVersion();

		switch (g_EngineVersion)
		{
			case Engine_Original: // Original Source Engine (used by The Ship)
				g_iSpec_FLMode = 5;
			case Engine_SourceSDK2006: // Episode 1 Source Engine (second major SDK)
				g_iSpec_FLMode = 5;
			case Engine_DarkMessiah: // Dark Messiah Multiplayer (based on original engine)
				g_iSpec_FLMode = 5;
			default:
				g_iSpec_FLMode = 6;
		}
	}
#endif

	RegisterCvars(); // Register Cvars
	SetConVarInt(hCvarLogWarnings, 0);
	SetConVarInt(hCvarEnabled, 0);

	HookConVars(); // Hook ConVars
	HookEvents(); // Hook Events

	AutoExecConfig(true, "afk_manager");

	RegisterCmds(); // Register Commands

	if (hCvarLogDays != INVALID_HANDLE)
		if (GetConVarInt(hCvarLogDays) > 0)
			PurgeOldLogs(); // Purge Old Log Files

	if (g_bLateLoad) // Account for Late Loading
		g_bWaitRound = false;
		
	AddUpdaterLibrary(); //auto-updater
}

public void OnMapStart()
{
	BuildLogFilePath();

	if (hCvarLogDays != INVALID_HANDLE)
		if (GetConVarInt(hCvarLogDays) > 0)
			PurgeOldLogs(); // Purge Old Log Files

	AutoExecConfig(true, "afk_manager"); // Execute Config
}

public void OnClientPutInServer(int client) // Client has joined server
{
	if (g_bEnabled)
	{
		InitializePlayer(client);

		CheckMinPlayers(); // Increment Player Count
	}
}

public void OnClientDisconnect_Post(int client) // Client has left server
{
	if (g_bEnabled)
	{
		UnInitializePlayer(client); // UnInitializePlayer since they are leaving the server.

		CheckMinPlayers();
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_bEnabled)
	{
		if (IsClientSourceTV(client) || IsFakeClient(client)) // Ignore Source TV & Bots
			return Plugin_Continue;

		if (cmdnum <= 0) // NULL Commands?
			return Plugin_Handled;

		if (g_hAFKTimer[client] != INVALID_HANDLE)
		{
			//if ((iButtons[client] != buttons) || ( (iMouse[client][0] != mouse[0]) || (iMouse[client][1] != mouse[1]) ))
			if ( (iButtons[client] != buttons) || ( (angles[0] != fEyeAngles[client][0]) || (angles[1] != fEyeAngles[client][1]) || (angles[2] != fEyeAngles[client][2]) ) )
			{
				if (IsClientObserver(client))
				{
					if (iObserverMode[client] == -1) // Player has an Invalid Observer Mode
					{
						iButtons[client] = buttons;
						fEyeAngles[client] = angles;
						return Plugin_Continue;
					}
					else if (iObserverMode[client] != 4) // Check Observer Mode in case it has changed
						iObserverMode[client] = GetEntProp(client, Prop_Send, "m_iObserverMode");

					if ((iObserverMode[client] == 4) && (iButtons[client] == buttons))
					{
						fEyeAngles[client] = angles;
						return Plugin_Continue;
					}

					if ( (iButtons[client] == buttons) && ( (FloatAbs(FloatSub(angles[0],fEyeAngles[client][0])) < 2.0) && (FloatAbs(FloatSub(angles[1],fEyeAngles[client][1])) < 2.0) && (FloatAbs(FloatSub(angles[2],fEyeAngles[client][2])) < 2.0) ) )
					{
						fEyeAngles[client] = angles;
						return Plugin_Continue;
					}
				}

				iButtons[client] = buttons;
				fEyeAngles[client] = angles;
				//iMouse[client] = mouse;
				if (bPlayerDeath[client])
					bPlayerDeath[client] = false;
				else
					if (bPlayerAFK[client])
					{
						Forward_OnClientBack(client);
						bPlayerAFK[client] = false;
					}
				//ResetPlayer(client, false);
			}
		}
	}
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) // Player Chat
{
	if (g_bEnabled)
		if (g_hAFKTimer[client] != INVALID_HANDLE)
			ResetPlayer(client, false); // Reset timer once player has said something in chat.
	return Plugin_Continue;
}


// Game Events
public Action Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	if (g_bEnabled)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));

		if (client > 0) // Check the client is not console/world?
			if (IsValidClient(client))
			{
				if (g_hAFKTimer[client] != INVALID_HANDLE)
				{
					g_iPlayerTeam[client] = GetEventInt(event, "team");

					if (g_iPlayerTeam[client] != g_iSpec_Team)
					{
						ResetObserver(client);
						ResetPlayer(client, false);
					}
				}
			}
	}
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	if (g_bEnabled)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));

		if (client > 0) // Check the client is not console/world?
			if (IsValidClient(client)) // Check client is not a bot or otherwise fake player.
			{
				if (g_hAFKTimer[client] != INVALID_HANDLE)
				{
					if (g_iPlayerTeam[client] == 0) // Unassigned Team? Fires in CSTRIKE?
						return Plugin_Continue;

					if (!IsClientObserver(client)) // Client is not an Observer/Spectator?
						if (IsPlayerAlive(client)) // Fix for Valve causing Unassigned to not be detected as an Observer in CSS?
							if (GetClientHealth(client) > 0) // Fix for Valve causing Unassigned to be alive?
							{
								ResetAttacker(client);
								ResetObserver(client);

								if (GetConVarFloat(hCvarSpawnTime) > 0.0) // Check if Spawn AFK is enabled.
								{
									g_iSpawnTime[client] = GetTime();
								}
							}
				}
			}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeathPost(Handle event, const char[] name, bool dontBroadcast)
{
	if (g_bEnabled)
	{
		int client = GetClientOfUserId(GetEventInt(event,"userid"));

		if (client > 0) // Check the client is not console/world?
			if (IsValidClient(client)) // Check client is not a bot or otherwise fake player.
			{
				if (g_hAFKTimer[client] != INVALID_HANDLE)
				{
					iPlayerAttacker[client] = GetClientOfUserId(GetEventInt(event,"attacker"));

					GetClientEyeAngles(client, fEyeAngles[client]);
					ResetSpawn(client);
					bPlayerDeath[client] = true;

					if (IsClientObserver(client))
					{
						iObserverMode[client] = GetEntProp(client, Prop_Send, "m_iObserverMode");
						iObserverTarget[client] = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
					}
				}
			}
	}
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bWaitRound = false; // Un-Pause Plugin on Map Start
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bWaitRound = true; // Pause Plugin During Map Transitions?
}

//Look for if a team has any transport gates left, if not pause the plugin
public Action Event_StructDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("type") == ND_TRANSPORT_GATE)
	{
		int 	client = GetClientOfUserId(event.GetInt("attacker")),	
			team = getOtherTeam(GetClientTeam(client));
		
		if (ND_HasNoTransportGates(team))
			g_bWaitRound = true; // Pause Plugin When all Transport Gates Die
	}
}

bool ND_HasNoTransportGates(team)
{
	// loop through all entities finding transport gates
	new loopEntity = INVALID_ENT_REFERENCE;
	while ((loopEntity = FindEntityByClassname(loopEntity, ND_TRANSPORT_NAME)) != INVALID_ENT_REFERENCE)
	{
		if (GetEntProp(loopEntity, Prop_Send, "m_iTeamNum") == team) //if the owner equals the team arg
		{
			return true;	
		}	
	}
	
	return false;
}

// Timers
public Action Timer_CheckPlayer(Handle Timer, int client) // General AFK Timers
{
	if(g_bEnabled) // Is the AFK Manager Enabled
	{
		if (GetEntityFlags(client) & FL_FROZEN) // Ignore FROZEN Clients
		{
			g_iAFKTime[client]++;
			return Plugin_Continue;
		}

		if (IsClientObserver(client))
		{
			int m_iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

			if (iObserverMode[client] == -1) // Invalid Observer Mode
			{
				iObserverMode[client] = m_iObserverMode;
				GetClientEyeAngles(client, fEyeAngles[client]);
				g_iAFKTime[client]++;
				return Plugin_Continue;
			}
			else if (iObserverMode[client] != m_iObserverMode) // Player changed Observer Mode
			{
				iObserverMode[client] = m_iObserverMode;

				if (iObserverMode[client] != g_iSpec_FLMode)
				{
					int m_hObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

					if ((iObserverTarget[client] == client) || (iObserverTarget[client] == iPlayerAttacker[client])) // Death Cam?
					{
						iObserverTarget[client] = m_hObserverTarget;
						return Plugin_Continue;
					}
					else
						iObserverTarget[client] = m_hObserverTarget;
				}
				SetClientAFK(client);
				return Plugin_Continue;
			}
			else if (iObserverMode[client] != g_iSpec_FLMode)
			{
				int m_hObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

				if (iObserverTarget[client] != m_hObserverTarget) // Player changed Observer Mode
				{
					if (!IsValidClient(iObserverTarget[client], false)) // Previous Target is now invalid
						iObserverTarget[client] = m_hObserverTarget;
					else if (iObserverTarget[client] == client) // Previous target was the themselves
						iObserverTarget[client] = m_hObserverTarget;
					else if (!IsPlayerAlive(iObserverTarget[client])) // Previous target has died
						iObserverTarget[client] = m_hObserverTarget;
					else
					{
						iObserverTarget[client] = m_hObserverTarget;
						SetClientAFK(client);
						return Plugin_Continue;
					}
				}
			}
		}
		

		int Time = GetTime();
		if (!bPlayerAFK[client]) // Player Marked as not AFK?
		{
			if ((g_iSpawnTime[client] > 0) && ((Time - g_iSpawnTime[client]) < 2)) // Check if player has just spawned
				SetClientAFK(client, false);
			else if ((!IsPlayerAlive(client)) && (iObserverTarget[client] == client)) // Player is in death cam?
				SetClientAFK(client, false);
			else
				SetClientAFK(client);

			return Plugin_Continue;
		}

		if (g_bWaitRound) // Are we waiting for the round to start
		{
			g_iAFKTime[client]++;
			return Plugin_Continue;
		}

		if ((bMovePlayers == false) && (bKickPlayers == false)) // Do we have enough players to start taking action
		{
			g_iAFKTime[client]++;
			return Plugin_Continue;
		}

		if ((g_iPlayerTeam[client] != 0) && (g_iPlayerTeam[client] != g_iSpec_Team)) // Make sure player is not Unassigned or Spectator
			if (!IsPlayerAlive(client) && (g_bExcludeDead)) // Excluding Dead players
			{
				g_iAFKTime[client]++;
				return Plugin_Continue;
			}


		int AdminsImmune = GetConVarInt(hCvarAdminsImmune);

		int AFKSpawnTimeleft = -1;
		int AFKSpawnTime;
		int cvarSpawnTime;

		if ((g_iSpawnTime[client] > 0) && (!IsPlayerAlive(client))) // Check Spawn Time and Player Alive
			ResetSpawn(client);

		if (g_iSpawnTime[client] > 0)
		{
			cvarSpawnTime = GetConVarInt(hCvarSpawnTime);

			if (cvarSpawnTime > 0)
			{
				AFKSpawnTime = Time - g_iSpawnTime[client];
				//if (AFKSpawnTime <= 1)
				//	AFKSpawnTimeleft = cvarSpawnTime;
				//else
				AFKSpawnTimeleft = cvarSpawnTime - AFKSpawnTime;
			}
		}

		int AFKTime;
		if (g_iAFKTime[client] >= 0)
			AFKTime = Time - g_iAFKTime[client];
		else
			AFKTime = 0;

		if (g_iPlayerTeam[client] != g_iSpec_Team) // Check we are not on the Spectator team
		{
			if (GetConVarBool(hCvarMoveSpec))
			{
				if (bMovePlayers == true)
				{
					if ( (AdminsImmune == 0) || (AdminsImmune == 2) || (!CheckAdminImmunity(client)) ) // Check Admin Immunity
					{
						if (g_iTimeToMove > 0)
						{
							int AFKMoveTimeleft = g_iTimeToMove - AFKTime;

							if (AFKMoveTimeleft >= 0)
							{
								if (AFKSpawnTimeleft >= 0)
									if (AFKSpawnTimeleft < AFKMoveTimeleft) // Spawn time left is less than total AFK time left
									{
										if (AFKSpawnTime >= cvarSpawnTime) // Take Action on AFK Spawn Player
										{
											ResetSpawn(client);
											if (g_iPlayerTeam[client] == 0) // Are we moving player from the Unassigned team AKA team 0?
												return MoveAFKClient(client, GetConVarBool(hCvarWarnUnassigned)); // Are we warning unassigned players?
											else
												return MoveAFKClient(client);
										}
										else if (AFKSpawnTime%AFK_WARNING_INTERVAL == 0) // Warn AFK Spawn Player
										{
											if ((cvarSpawnTime - AFKSpawnTime) <= GetConVarInt(hCvarWarnSpawnTime))
												AFK_PrintToChat(client, "%t", "Spawn_Move_Warning", AFKSpawnTimeleft);
										}
										return Plugin_Continue;
									}

								if (AFKTime >= g_iTimeToMove) // Take Action on AFK Player
								{
									if (g_iPlayerTeam[client] == 0) // Are we moving player from the Unassigned team AKA team 0?
										return MoveAFKClient(client, GetConVarBool(hCvarWarnUnassigned)); // Are we warning unassigned players?
									else
										return MoveAFKClient(client);
								}
								else if (AFKTime%AFK_WARNING_INTERVAL == 0) // Warn AFK Player
								{
									if ((g_iTimeToMove - AFKTime) <= GetConVarInt(hCvarWarnTimeToMove))
										AFK_PrintToChat(client, "%t", "Move_Warning", AFKMoveTimeleft);
									return Plugin_Continue;
								}
								return Plugin_Continue; // Fix for AFK Spawn Kick Notifications
							}
						}
					}
				}
			}
		}

		int KickPlayers = GetConVarInt(hCvarKickPlayers);
		
		if (KickPlayers > 0)
			if (bKickPlayers == true)
			{
				if ((KickPlayers == 2) && (g_iPlayerTeam[client] == g_iSpec_Team)) // Kicking is set to exclude spectators. Player is on the spectator team. Spectators should not be kicked.
					return Plugin_Continue;
				else
				{
					if ( (AdminsImmune == 0) || (AdminsImmune == 3) || (!CheckAdminImmunity(client)) ) // Check Admin Immunity
					{
						if (g_iTimeToKick > 0)
						{
							int AFKKickTimeleft = g_iTimeToKick - AFKTime;

							if (AFKKickTimeleft >= 0)
							{
								if (AFKSpawnTimeleft >= 0)
									if (AFKSpawnTimeleft < AFKKickTimeleft) // Spawn time left is less than total AFK time left
									{
										if (AFKSpawnTime >= cvarSpawnTime) // Take Action on AFK Spawn Player
											return KickAFKClient(client);
										else if (AFKSpawnTime%AFK_WARNING_INTERVAL == 0) // Warn AFK Spawn Player
										{
											if ((cvarSpawnTime - AFKSpawnTime) <= GetConVarInt(hCvarWarnSpawnTime))
												AFK_PrintToChat(client, "%t", "Spawn_Kick_Warning", AFKSpawnTimeleft);
											return Plugin_Continue;
										}
									}

								if (AFKTime >= g_iTimeToKick) // Take Action on AFK Player
									return KickAFKClient(client);
								else if (AFKTime%AFK_WARNING_INTERVAL == 0) // Warn AFK Player
								{
									if ((g_iTimeToKick - AFKTime) <= GetConVarInt(hCvarWarnTimeToKick))
										AFK_PrintToChat(client, "%t", "Kick_Warning", AFKKickTimeleft);
									return Plugin_Continue;
								}
							}
							else
								return KickAFKClient(client);
						}
					}
				}
			}
	}

	//g_hAFKTimer[client] = INVALID_HANDLE;
	return Plugin_Continue;
}


// Move/Kick Functions
Action MoveAFKClient(int client, bool Advertise=true) // Move AFK Client to Spectator Team
{
	Action ForwardResult = Plugin_Continue;

	if (g_iSpawnTime[client] != -1)
		ForwardResult = Forward_OnAFKEvent("afk_spawn_move", client);
	else
		ForwardResult = Forward_OnAFKEvent("afk_move", client);

	if (ForwardResult != Plugin_Continue)
	{
		if (g_bLogWarnings)
		{
			char Action_Name[32];
			Action_Name = ActionToString(ForwardResult);
			LogToFile(AFKM_LogFile, "AFK Manager Event: MoveAFKClient has been requested to: %s by an external plugin this action will affect the event outcome.", Action_Name);
		}
		return ForwardResult;
	}

	char f_Name[MAX_NAME_LENGTH];
	GetClientName(client, f_Name, sizeof(f_Name));

	if (Advertise) // Are we announcing the move to everyone?
	{
		int Announce = GetConVarInt(hCvarMoveAnnounce);

		if (Announce == 0)
			AFK_PrintToChat(client, "%t", "Move_Announce", f_Name);
		else if (Announce == 1)
			AFK_PrintToChat(0, "%t", "Move_Announce", f_Name);
		else
		{
			for(int i = 1; i <= MaxClients; i++)
				if (IsClientConnected(i))
					if (IsClientInGame(i))
						if ((i == client) || (GetUserAdmin(i) != INVALID_ADMIN_ID))
							AFK_PrintToChat(i, "%t", "Move_Announce", f_Name);
		}
	}

	if (GetConVarBool(hCvarLogMoves))
		LogToFile(AFKM_LogFile, "%T", "Move_Log", LANG_SERVER, client);

	ChangeClientTeam(client, g_iSpec_Team); // Move AFK Player to Spectator

	return Plugin_Continue; // Check This?
}

Action KickAFKClient(int client) // Kick AFK Client
{
	Action ForwardResult = Forward_OnAFKEvent("afk_kick", client);

	if (ForwardResult != Plugin_Continue)
	{
		if (g_bLogWarnings)
		{
			char Action_Name[32];
			Action_Name = ActionToString(ForwardResult);
			LogToFile(AFKM_LogFile, "AFK Manager Event: KickAFKClient has been requested to: %s by an external plugin this action will affect the event outcome.", Action_Name);
		}
		return ForwardResult;
	}

	char f_Name[MAX_NAME_LENGTH];
	GetClientName(client, f_Name, sizeof(f_Name));

	int Announce = GetConVarInt(hCvarKickAnnounce);
	if (Announce == 1)
		AFK_PrintToChat(0, "%t", "Kick_Announce", f_Name);
	else if (Announce == 2)
	{
		for(int i = 1; i <= MaxClients; i++)
			if (IsClientConnected(i))
				if (IsClientInGame(i))
					if (GetUserAdmin(i) != INVALID_ADMIN_ID)
						AFK_PrintToChat(i, "%t", "Kick_Announce", f_Name);
	}

	if (GetConVarBool(hCvarLogKicks))
		LogToFile(AFKM_LogFile, "%T", "Kick_Log", LANG_SERVER, client);

	if (g_bForceLanguage)
		KickClient(client, "[%s] %T", g_sPrefix, "Kick_Message", LANG_SERVER);
	else
		KickClient(client, "[%s] %t", g_sPrefix, "Kick_Message");
	return Plugin_Continue;
}

bool CheckAdminImmunity(int client) // Check Admin Immunity
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	AdminId admin = GetUserAdmin(client);

	if(admin != INVALID_ADMIN_ID) // Check if player is an admin
	{
		char flags[8];
		AdminFlag flag;

		GetConVarString(hCvarAdminsFlag, flags, sizeof(flags));

		if (!StrEqual(flags, "", false)) // Are we checking for specific admin flags?
		{
			if (FindFlagByChar(flags[0], flag)) // Is the admin flag we are checking valid?
				if (GetAdminFlag(admin, flag)) // Check if the admin has the correct immunity flag.
					return true;
		}
		else
			return true;
	}
	return false;
}
