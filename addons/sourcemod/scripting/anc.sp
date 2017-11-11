#include <sdktools_functions>
#include <chat>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

char gen_dir[] = "cfg/sourcemod/anc/";

char file_names[64]		= "names.ini";
char file_clans[64]		= "clans.ini";
char file_newnames[64]	= "newnames.ini";
char file_newclans[64]	= "newclans.ini";
char file_whitelist[64]	= "whitelist.ini";
char adminflag[5]		= "z";

int bansamount,
	banstime;

bool enabled,
	 show_msg;

ConVar	sm_anc_enabled,
		sm_anc_filenames,
		sm_anc_fileclans,
		sm_anc_filenewnames,
		sm_anc_filenewclans,
		sm_anc_filewhitelist,
		sm_anc_bansamount,
		sm_anc_banstime,
		sm_anc_aminflag,
		sm_anc_showmsg;

ArrayList	names,
			clans,
			newnames,
			newclans,
			whitelist;

int ban[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "Auto Name Changer",
	author		= "Exle",
	description = "Replaces forbidden nicknames and clan tag",
	version		= "1.4.3",
	url			= "http://steamcommunity.com/id/ex1e/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("SetClientName");
	MarkNativeAsOptional("CS_GetClientClanTag");
	MarkNativeAsOptional("CS_SetClientClanTag");
	MarkNativeAsOptional("GetUserMessageType");

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("anc.phrases");

	sm_anc_enabled		= CreateConVar("sm_anc_enabled",		"1",			"1 / 0 | Вкл / Выкл", _, true, 0.0, true, 1.0);
	sm_anc_filenames	= CreateConVar("sm_anc_filenames",		file_names,		"Файл запрещенных ников / Для отключения оставьте пустым");
	sm_anc_fileclans	= CreateConVar("sm_anc_fileclans",		file_clans,		"Файл запрещенных клан тегов / Для отключения оставьте пустым");
	sm_anc_filenewnames	= CreateConVar("sm_anc_filenewnames",	file_newnames,	"Файл новых ников / Если больше одной строки, то будет выбрана случайная строка");
	sm_anc_filenewclans	= CreateConVar("sm_anc_filenewclans",	file_newclans,	"Файл новых клан тегов / Если больше одной строки, то будет выбрана случайная строка");
	sm_anc_filewhitelist= CreateConVar("sm_anc_filewhitelist",	file_whitelist,	"Файл белого списка / Для отключения оставьте пустым");

	sm_anc_bansamount	= CreateConVar("sm_anc_bansamount",		"3",			"Количество изменений ника плагином до бана / Для отключения -1", _, true, -1.0);
	sm_anc_banstime		= CreateConVar("sm_anc_banstime",		"30",			"Время бана", _, true, 0.0);
	sm_anc_aminflag		= CreateConVar("sm_anc_adminflag",		adminflag,		"Флаг админов для иммунитета / Для отключения оставьте пустым");
	sm_anc_showmsg		= CreateConVar("sm_anc_showmsg",		"1",			"Показывать сообщения плагина в чате (silent mode) / 1 / 0 | Вкл / Выкл", _, true, 0.0, true, 1.0);

	sm_anc_filenames.AddChangeHook(OnConVarChanged);
	sm_anc_fileclans.AddChangeHook(OnConVarChanged);
	sm_anc_filenewnames.AddChangeHook(OnConVarChanged);
	sm_anc_filenewclans.AddChangeHook(OnConVarChanged);
	sm_anc_filewhitelist.AddChangeHook(OnConVarChanged);
	sm_anc_bansamount.AddChangeHook(OnConVarChanged);
	sm_anc_banstime.AddChangeHook(OnConVarChanged);
	sm_anc_aminflag.AddChangeHook(OnConVarChanged);
	sm_anc_showmsg.AddChangeHook(OnConVarChanged);

	names		= new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	newnames	= new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	clans		= new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	newclans	= new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	whitelist	= new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));

	HookEvent("player_changename", player_changename, EventHookMode_Pre);

	HookMsg();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		OnClientPutInServer(i);
	}

	AutoExecConfig(true, _, "sourcemod/anc");
}

public void OnConfigsExecuted()
{
	enabled = sm_anc_enabled.BoolValue;
	sm_anc_filenames.GetString(file_names, 64);
	sm_anc_fileclans.GetString(file_clans, 64);
	sm_anc_filenewnames.GetString(file_newnames, 64);
	sm_anc_filenewclans.GetString(file_newclans, 64);
	sm_anc_filewhitelist.GetString(file_whitelist, 64);
	bansamount	= sm_anc_bansamount.IntValue;
	banstime	= sm_anc_banstime.IntValue;
	sm_anc_aminflag.GetString(adminflag, 5);
	show_msg = sm_anc_showmsg.BoolValue;
}

public void OnPluginEnd()
{
	delete names;
	delete clans;
	delete newnames;
	delete newclans;
	delete whitelist;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == sm_anc_enabled)
	{
		enabled = convar.BoolValue;
	}
	else if (convar == sm_anc_filenames)
	{
		strCopy(file_names, 64, oldValue, newValue);
		CreateNGetFromFile(names, file_names);
	}
	else if (convar == sm_anc_fileclans)
	{
		strCopy(file_clans, 64, oldValue, newValue);
		CreateNGetFromFile(clans, file_clans);
	}
	else if (convar == sm_anc_filenewnames)
	{
		strCopy(file_newnames, 64, oldValue, newValue);
		CreateNGetFromFile(newnames, file_newnames);
	}
	else if (convar == sm_anc_filenewclans)
	{
		strCopy(file_newclans, 64, oldValue, newValue);
		CreateNGetFromFile(newclans, file_newclans);
	}
	else if (convar == sm_anc_filewhitelist)
	{
		strCopy(file_whitelist, 64, oldValue, newValue);
		CreateNGetFromFile(whitelist, file_whitelist);
	}
	else if (convar == sm_anc_bansamount)
	{
		bansamount = convar.IntValue;
	}
	else if (convar == sm_anc_banstime)
	{
		banstime = convar.IntValue;
	}
	else if (convar == sm_anc_aminflag)
	{
		strcopy(adminflag, 5, newValue);
	}
	else if (convar == sm_anc_showmsg)
	{
		show_msg = convar.BoolValue;
	}
}

public void OnMapStart()
{
	CreateDir(gen_dir);

	CreateNGetFromFile(names, file_names);
	CreateNGetFromFile(clans, file_clans);
	CreateNGetFromFile(newnames, file_newnames);
	CreateNGetFromFile(newclans, file_newclans);
	CreateNGetFromFile(whitelist, file_whitelist);
}

public void OnClientPutInServer(int client)
{
	if (!enabled || !file_names[0])
	{
		return;
	}

	ban[client] = 0;

	if (IsFakeClient(client) || IsClientAdmin(client))
	{
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, MAX_NAME_LENGTH);

	if (FindInArray(names, name) && !FindInArray(whitelist, name, false))
	{
		GetRandomStringFromArray(newnames, name, MAX_NAME_LENGTH);
		ChangeClientName(client, name);
	}
}

public void OnClientSettingsChanged(int client)
{
	if (GetFeatureStatus(FeatureType_Native, "CS_GetClientClanTag") != FeatureStatus_Available || !enabled || !file_clans[0] || !IsClientInGame(client) || IsFakeClient(client) || IsClientAdmin(client))
	{
		return;
	}

	char clan[MAX_NAME_LENGTH];

	CS_GetClientClanTag(client, clan, sizeof(clan));

	if (FindInArray(clans, clan) && !FindInArray(whitelist, clan, false))
	{
		if (!GetRandomStringFromArray(newclans, clan, MAX_NAME_LENGTH))
		{
			clan[0] = '\0';
		}

		ChangeClientClan(client, clan);
	}
}

public Action player_changename(Event event, const char[] name, bool dontBroadcast)
{
	if (!enabled || !file_names[0])
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if (IsFakeClient(client) || IsClientAdmin(client))
	{
		return Plugin_Continue;
	}

	char newname[MAX_NAME_LENGTH], 
		 oldname[MAX_NAME_LENGTH];

	event.GetString("newname", newname, MAX_NAME_LENGTH);
	event.GetString("oldname", oldname, MAX_NAME_LENGTH);

	if (FindInArray(names, newname) && !FindInArray(whitelist, newname, false))
	{
		if (!GetRandomStringFromArray(newnames, newname, MAX_NAME_LENGTH))
		{
			strcopy(newname, MAX_NAME_LENGTH, oldname);
		}

		ChangeClientName(client, newname);

		if (!dontBroadcast)
		{
			event.BroadcastDisabled = true;
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action SayText2_Bf(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	return SayText2_Processing(msg);
}

public Action SayText2_Pb(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
	return SayText2_Processing(_, msg);
}

Action SayText2_Processing(BfRead bf = null, Protobuf pb = null)
{
	if (!enabled || !file_names[0])
	{
		return Plugin_Continue;
	}

	char message[255],
		 oldname[MAX_NAME_LENGTH],
		 newname[MAX_NAME_LENGTH];

	if (bf != null)
	{
		bf.ReadByte();
		bf.ReadByte();
		bf.ReadString(message, 255);
		bf.ReadString(oldname, MAX_NAME_LENGTH);
		bf.ReadString(newname, MAX_NAME_LENGTH);
	}
	else
	{
		pb.ReadString("params", message, 255, 1);
		pb.ReadString("params", oldname, MAX_NAME_LENGTH, 2);
		pb.ReadString("params", newname, MAX_NAME_LENGTH, 3);
	}

	if (!IsClientAdmin(GetClientByName(newname)) && StrContains(message, "Name_Change") != -1 && (FindInArray(names, newname) && !FindInArray(whitelist, newname, false) || FindInArray(names, oldname) && !FindInArray(whitelist, oldname, false)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void HookMsg()
{
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available)
	{
		if (GetUserMessageType() == UM_BitBuf)
		{
			HookUserMessage(GetUserMessageId("SayText2"), SayText2_Bf, true);
		}
		else
		{
			HookUserMessage(GetUserMessageId("SayText2"), SayText2_Pb, true);
		}
	}
}

void CreateNGetFromFile(ArrayList array, const char[] file_path)
{
	array.Clear();

	if (file_path[0])
	{
		CreateFile("%s%s", gen_dir, file_path);
		SetArrayFromFile(array, "%s%s", gen_dir, file_path);
	}
}


int GetClientByName(const char[] name)
{
	char tmp_name[MAX_NAME_LENGTH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		GetClientName(i, tmp_name, MAX_NAME_LENGTH);

		if (strcmp(name, tmp_name) == 0)
		{
			continue;
		}

		return i;
	}

	return -1;
}

bool IsClientAdmin(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return false;
	}

	AdminId admin = GetUserAdmin(client);
	if (admin == INVALID_ADMIN_ID || !adminflag[0])
	{
		return false;
	}

	AdminFlag flag;

	if (!FindFlagByChar(adminflag[0], flag) || !GetAdminFlag(admin, flag))
	{
		return false;
	}

	return true;
}

void ChangeClientName(int client, const char[] newname)
{
	BanOptions(client);

	if (GetFeatureStatus(FeatureType_Native, "SetClientName") == FeatureStatus_Available)
	{
		SetClientName(client, newname);
	}
	else
	{
		SetClientInfo(client, "name", newname);
	}

	if (show_msg)
	{
		Chat(client, "%c[ANC]%c %t", 3, 1, "Rename", 3, newname);
	}
}

void ChangeClientClan(int client, const char[] newclan)
{
	if (GetFeatureStatus(FeatureType_Native, "CS_SetClientClanTag") == FeatureStatus_Available)
	{
		CS_SetClientClanTag(client, newclan);

		if (show_msg)
		{
			Chat(client, "%c[ANC]%c %t", 3, 1, "Renameclan", 3, newclan);
		}
	}
}

void BanOptions(int client)
{
	if (bansamount == -1)
	{
		return;
	}

	if (++ban[client] != bansamount && show_msg)
	{
		Chat(client, "%c[ANC]%c %t", 3, 1, "For_Ban");
		Chat(client, "%c[ANC]%c %t", 3, 1, "Warning", 3, ban[client], 1, 3, bansamount);
	}
	else if (ban[client] >= bansamount)
	{
		ServerCommand("sm_ban #%i %i \"Bad nickname\"", GetClientUserId(client), banstime);

		return;
	}
}

bool FindInArray(ArrayList array, const char[] buffer, bool substring = true)
{
	if (!array.Length)
	{
		return false;
	}

	char string[MAX_NAME_LENGTH];

	for (int i = 0; i < array.Length; i++)
	{
		array.GetString(i, string, MAX_NAME_LENGTH);

		if (substring && StrContains(buffer, string, false) != -1 || !substring && strcmp(buffer, string, false) == 0)
		{
			return true;
		}
	}

	return false;
}

int GetRandomStringFromArray(ArrayList array, char[] buffer, int maxlen)
{
	if (!array.Length)
	{
		return -1;
	}

	return array.GetString(GetRandomInt(0, array.Length - 1), buffer, maxlen);
}

void SetArrayFromFile(ArrayList array, char[] path_file, any ...)
{
	char buffer[PLATFORM_MAX_PATH];
	VFormat(buffer, PLATFORM_MAX_PATH, path_file, 3);

	if (!FileExists(buffer))
	{
		return;
	}

	File fFile = OpenFile(buffer, "r");

	if (fFile == null)
	{
		return;
	}

	int position;
	while(!fFile.EndOfFile() && fFile.ReadLine(buffer, PLATFORM_MAX_PATH))
	{
		if ((position = StrContains(buffer, "//")) != -1)
		{
			buffer[position] = '\0';
		}

		if ((position = StrContains(buffer, "#")) != -1)
		{
			buffer[position] = '\0';
		}

		if ((position = StrContains(buffer, ";")) != -1)
		{
			buffer[position] = '\0';
		}
		
		TrimString(buffer);
		
		if (!buffer[0])
		{
			continue;
		}

		array.PushString(buffer);
	}

	delete fFile;
}

void strCopy(char[] file_path, int maxlen, const char[] oldValue, const char[] newValue)
{
	if (!newValue[0])
	{
		if (oldValue[0])
		{
			strcopy(file_path, maxlen, oldValue);
		}

		return;
	}

	strcopy(file_path, maxlen, newValue);

	if (!oldValue[0])
	{
		return;
	}
	
	char buffer[2][PLATFORM_MAX_PATH];

	FormatEx(buffer[0], PLATFORM_MAX_PATH, "%s%s", gen_dir, oldValue);
	FormatEx(buffer[1], PLATFORM_MAX_PATH, "%s%s", gen_dir, file_path);

	FileCopy(buffer[0], buffer[1]);
}

void CreateDir(const char[] path_dir, any ...)
{
	char buffer[PLATFORM_MAX_PATH];
	VFormat(buffer, PLATFORM_MAX_PATH, path_dir, 2);

	if (!DirExists(buffer))
	{
		CreateDirectory(buffer, 755);
	}
}

void CreateFile(const char[] path_file, any ...)
{
	char buffer[PLATFORM_MAX_PATH];
	VFormat(buffer, PLATFORM_MAX_PATH, path_file, 2);

	if (!FileExists(buffer))
	{
		File fFile = OpenFile(buffer, "w");
		delete fFile;
	}
}

stock bool FileCopy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "r");

	if (file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "w");

	if (file_destination == null)
	{
		delete file_source;
		return false;
	}

	char buffer[MAX_NAME_LENGTH];

	while (!file_source.EndOfFile() && file_source.ReadLine(buffer, MAX_NAME_LENGTH))
	{
		file_destination.WriteLine(buffer);
	}

	delete file_source;
	delete file_destination;

	return true;
}