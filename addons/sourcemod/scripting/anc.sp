#include <sourcemod>
#include <sdktools_functions>
#include <anc_version>

#pragma semicolon 1
#pragma newdecls required

#define GEN_DIR 		"cfg/sourcemod/anc/"

#define ARRAY_CLANS 	0
#define ARRAY_NAMES 	1
#define ARRAY_NEWCLANS 	2
#define ARRAY_NEWNAMES 	3
#define ARRAY_WHITELIST 4
#define ARRAY_MAX 		5

#define MODE_CM (1 << 0)	/**< Complete match			'a' */
#define MODE_PM (1 << 1)	/**< Partial match			'b' */
#define MODE_CR (1 << 2)	/**< Complete replacement	'c' */
#define MODE_PR (1 << 3)	/**< Partial replacement	'd' */
#define MODE_CS (1 << 4)	/**< Case sensitive			'e' */
#define MODE_CI (1 << 5)	/**< Case insensitive		'f' */

int anc_bansamount,
	anc_banstime,
	anc_adminflags;

bool anc_enabled,
	anc_engine,
	anc_pb;

ArrayList anc_arrays[ARRAY_MAX];

int ban[MAXPLAYERS + 1];

int lastflags;
char newname[MAX_NAME_LENGTH],
	match[MAX_NAME_LENGTH];

public Plugin myinfo =
{
	name		= "Auto Name Changer",
	author		= "Exle",
	description = "Replaces forbidden nicknames and clan tag",
	version		= VERSION,
	url			= "https://steamcommunity.com/profiles/76561198013509278"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	anc_engine = GetEngineVersion() == Engine_CSGO;
	anc_pb = GetUserMessageType() == UM_Protobuf;
}

public void OnPluginStart()
{
	LoadTranslations("anc.phrases");

	ConVar cvar;
	(cvar = CreateConVar("sm_anc_enabled", "1", "0 - Disabled / 1 - Enabled", _, true, 0.0, true, 1.0)).AddChangeHook(OnChangeEnabled); OnChangeEnabled(cvar, NULL_STRING, NULL_STRING);
	(cvar = CreateConVar("sm_anc_bansamount", "3", "Amount of changes nickname to ban / 0 - Disabled", _, true, 0.0)).AddChangeHook(OnChangeBansAmount); OnChangeBansAmount(cvar, NULL_STRING, NULL_STRING);
	(cvar = CreateConVar("sm_anc_banstime", "30", "Ban time", _, true, 0.0)).AddChangeHook(OnChangeBansTime); OnChangeBansTime(cvar, NULL_STRING, NULL_STRING);
	(cvar = CreateConVar("sm_anc_adminflags", "z", "Admin flags to exclude from scan")).AddChangeHook(OnChangeFlags);
	char buffer[24]; cvar.GetString(buffer, 24); OnChangeFlags(cvar, NULL_STRING, buffer);

	for (int i; i < ARRAY_MAX; ++i)
	{
		anc_arrays[i] = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH * 3));
	}

	HookEvent("player_changename", player_changename);

	UserMsg UMsg = GetUserMessageId("SayText2");
	if (UMsg != INVALID_MESSAGE_ID)
	{
		HookUserMessage(UMsg, SayText2, true);
	}

	for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i))
	{
		OnClientPostAdminCheck(i);
	}

	AutoExecConfig(_, _, "sourcemod/anc");
}

public void OnChangeEnabled(ConVar convar, const char[] oldValue, const char[] newValue)
{
	anc_enabled = convar.BoolValue;
}

public void OnChangeBansAmount(ConVar convar, const char[] oldValue, const char[] newValue)
{
	anc_bansamount = convar.IntValue;
}

public void OnChangeBansTime(ConVar convar, const char[] oldValue, const char[] newValue)
{
	anc_banstime = convar.IntValue;
}

public void OnChangeFlags(ConVar convar, const char[] oldValue, const char[] newValue)
{
	anc_adminflags = ReadFlagString(newValue);
}

public void OnMapStart()
{
	char files[ARRAY_MAX][PLATFORM_MAX_PATH] = {
		GEN_DIR ... "clans.txt",
		GEN_DIR ... "names.txt",
		GEN_DIR ... "newclans.txt",
		GEN_DIR ... "newnames.txt",
		GEN_DIR ... "whitelist.txt"
	};

	for (int i; i < ARRAY_MAX; ++i)
	{
		GetArrayFromFile(anc_arrays[i], files[i]);
	}
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	if (!anc_enabled || GetUserFlagBits(client) & anc_adminflags)
	{
		return Plugin_Continue;
	}

	char buffer[MAX_NAME_LENGTH];
	kv.GetString("tag", buffer, MAX_NAME_LENGTH);
	if (buffer[0] && !FindInWhiteList(client, buffer) && FindInArray(ARRAY_CLANS, buffer) && GetNewName(buffer, buffer, MAX_NAME_LENGTH))
	{
		kv.SetString("tag", buffer);
		PrintToChat(client, "%s\x01[\x04ANC\x01] %t\x04 %s", anc_engine ? " " : NULL_STRING, "Rename Clan", buffer);
	}

	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	ban[client] = 0;
	if (!anc_enabled || IsFakeClient(client) || GetUserFlagBits(client) & anc_adminflags)
	{
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, MAX_NAME_LENGTH);

	if (FindName(client, name) && GetNewName(name, name, MAX_NAME_LENGTH))
	{
		SetNewName(client, name);
		Warn(client);
	}
}

public Action player_changename(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!anc_enabled || IsFakeClient(client) || GetUserFlagBits(client) & anc_adminflags)
	{
		return Plugin_Continue;
	}

	char client_name[MAX_NAME_LENGTH];
	event.GetString("newname", client_name, MAX_NAME_LENGTH);

	if (FindName(client, client_name) && GetNewName(client_name, client_name, MAX_NAME_LENGTH))
	{
		if (!dontBroadcast)
		{
			event.BroadcastDisabled = true;
		}

		SetNewName(client, client_name);
		Warn(client);
	}

	return Plugin_Continue;
}

public Action SayText2(UserMsg msg_id, Handle msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!anc_enabled)
	{
		return Plugin_Continue;
	}

	char message[255],
		 oldname[MAX_NAME_LENGTH],
		 name[MAX_NAME_LENGTH];

	int client;

	if (anc_pb)
	{
		Protobuf pb = UserMessageToProtobuf(view_as<Handle>(msg));
		client = pb.ReadInt("ent_idx");
		pb.ReadString("msg_name", message, 255);
		pb.ReadString("params", oldname, MAX_NAME_LENGTH, 0);
		pb.ReadString("params", name, MAX_NAME_LENGTH, 1);
	}
	else
	{
		BfRead bf = UserMessageToBfRead(view_as<Handle>(msg));
		client = bf.ReadByte();
		bf.ReadByte();
		bf.ReadString(message, 255);
		bf.ReadString(oldname, MAX_NAME_LENGTH);
		bf.ReadString(name, MAX_NAME_LENGTH);
	}

	if (!IsFakeClient(client) && !(GetUserFlagBits(client) & anc_adminflags) && StrContains(message, "Name_Change") != -1 && (FindName(client, name) || FindName(client, oldname)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void Warn(int client)
{
	if (anc_bansamount == -1)
	{
		return;
	}

	if (++ban[client] < anc_bansamount)
	{
		PrintToChat(client, "%s\x01[\x04ANC\x01] %t", anc_engine ? " " : NULL_STRING, "For Ban");
		PrintToChat(client, "%s\x01[\x04ANC\x01] %t\x04 %d\x01/\x04%d", anc_engine ? " " : NULL_STRING, "Warning", ban[client], anc_bansamount);
	}
	else if (ban[client] >= anc_bansamount)
	{
		ServerCommand("sm_ban #%d %d Bad nickname", GetClientUserId(client), anc_banstime);
	}
}

void SetNewName(int client, const char[] name)
{
	SetClientInfo(client, "name", name);
	PrintToChat(client, "%s\x01[\x04ANC\x01] %t\x04 %s", anc_engine ? " " : NULL_STRING, "Rename Name", name);
}

int GetNewName(const char[] name, char[] buffer, int maxlength)
{
	int fl = GetFlags();
	if (fl & MODE_PR)
	{
		strcopy(buffer, maxlength, name);
		ReplaceString(buffer, maxlength, match, newname, view_as<bool>(fl & MODE_CS));
	}
	else
	{
		strcopy(buffer, maxlength, newname);
	}

	return strlen(buffer);
}

bool FindName(int client, const char[] name)
{
	return !FindInWhiteList(client, name) && FindInArray(ARRAY_NAMES, name);
}

bool FindInWhiteList(int client, const char[] name)
{
	char string[MAX_NAME_LENGTH];
	for (int i; i < 4; ++i)
	{
		if (!i)
		{
			strcopy(string, MAX_NAME_LENGTH, name);
		}
		else
		{
			GetClientAuthId(client, view_as<AuthIdType>(i), string, MAX_NAME_LENGTH);
		}

		if (FindInArray(ARRAY_WHITELIST, string))
		{
			return true;
		}
	}

	return false;
}

bool FindInArray(int index, const char[] name, int flags = 0)
{
	char string[MAX_NAME_LENGTH * 3];
	char buffer[16];

	for (int i, length = anc_arrays[index].Length, fl; i < length; ++i)
	{
		anc_arrays[index].GetString(i, string, MAX_NAME_LENGTH * 3);

		if (index != ARRAY_WHITELIST)
		{
			if (!GetParam(string, "new", newname, MAX_NAME_LENGTH))
			{
				if (!GetRandomStringFromArray(anc_arrays[index + 2], newname, MAX_NAME_LENGTH))
				{
					strcopy(newname, MAX_NAME_LENGTH, "undefined");
				}
			}

			GetParam(string, "mode", buffer, 16);
			lastflags = CheckBadFlags(ReadFlagString(buffer));

			RemoveParams(string);

			fl = !flags ? lastflags : flags;
		}
		else
		{
			fl = MODE_CM | MODE_CR | MODE_CI;
		}

		if ((fl & MODE_CM) && !strcmp(name, string, view_as<bool>(fl & MODE_CS)) || (fl & MODE_PM) && StrContains(name, string, view_as<bool>(fl & MODE_CS)) != -1)
		{
			if (index != ARRAY_WHITELIST)
			{
				strcopy(match, MAX_NAME_LENGTH, string);
			}

			return true;
		}
	}

	return false;
}

int GetParam(const char[] string, char[] param, char[] buffer, int maxlength)
{
	char tmp[64] = 0x2d2d20;
	StrCat(tmp, 64, param);

	int idx[2];
	if ((idx[0] = StrContains(string, tmp, false)) != -1)
	{
		strcopy(tmp, 64, string[(idx[0] += (idx[1] = strlen(tmp)) + (IsCharSpace(string[idx[0] + idx[1]]) ? 1 : 0))]);
		TrimString(tmp);
		if (tmp[0] == '\"' && (idx[1] = StrContains(tmp[1], "\"")) != -1 || tmp[0] == '\'' && (idx[1] = StrContains(tmp[1], "\'")) != -1)
		{
			tmp[idx[1] + 1] = 0;
			TrimString(tmp[1]);
			strcopy(buffer, maxlength, tmp[1]);
		}
		else if (SplitString(tmp, " ", buffer, maxlength) == -1)
		{
			BreakString(tmp, buffer, maxlength);
		}

		return strlen(buffer);
	}

	return 0;
}

void RemoveParams(char[] string)
{
	int idx;
	if ((idx = StrContains(string, " --")) != -1)
	{
		string[idx] = 0;
	}
}

int GetFlags()
{
	return lastflags ? lastflags : MODE_CM | MODE_PR | MODE_CI;
}

int CheckBadFlags(int fl)
{
	if (!(fl & MODE_CM) && !(fl & MODE_PM)) fl |= MODE_PM;
	if (!(fl & MODE_CR) && !(fl & MODE_PR)) fl |= MODE_CR;
	if (!(fl & MODE_CS) && !(fl & MODE_CI)) fl |= MODE_CI;

	return fl;
}

int GetRandomStringFromArray(ArrayList array, char[] buffer, int maxlength)
{
	int size = array.Length;
	if (!size)
	{
		return 0;
	}

	return array.GetString(GetRandomInt(0, size - 1), buffer, maxlength);
}

void GetArrayFromFile(ArrayList array, char[] file_path)
{
	array.Clear();

	File hFile = OpenFile(file_path, "r");
	if (!hFile)
	{
		LogError("Filed to open '%s'", file_path);
		return;
	}

	int position;
	while(!hFile.EndOfFile() && hFile.ReadLine(file_path, PLATFORM_MAX_PATH))
	{
		if ((position = StrContains(file_path, "//")) != -1)
		{
			file_path[position] = 0;
		}

		if (TrimString(file_path) && file_path[0])
		{
			array.PushString(file_path);
		}
	}

	delete hFile;
}